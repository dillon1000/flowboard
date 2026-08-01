import Fluent
import Vapor

struct TaskController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let tasks = routes.grouped("tasks")
        tasks.get(use: index)
        tasks.get("search", use: search)
        tasks.get(":taskID", use: show)
        tasks.post(use: create)
        tasks.patch(":taskID", use: update)
        tasks.post(":taskID", "move", use: move)
        tasks.delete(":taskID", use: delete)
    }

    func index(req: Request) async throws -> Page<TaskResponse> {
        try await taskPage(req: req)
    }

    func search(req: Request) async throws -> Page<TaskResponse> {
        guard let query = clean(req.query[String.self, at: "q"]) else {
            throw Abort(.badRequest, reason: "Add a non-empty q search parameter.")
        }
        guard query.count <= 120 else {
            throw Abort(.unprocessableEntity, reason: "Search terms cannot exceed 120 characters.")
        }
        return try await taskPage(req: req)
    }

    func show(req: Request) async throws -> TaskResponse {
        let task = try await findTask(req, permission: .view)
        let board = try await requiredBoard(for: task, on: req.db)
        return try TaskResponse(task: task, boardName: board.name)
    }

    /// Applies supported filters before pagination so counts and page boundaries
    /// describe the filtered result. Query values are bound by Fluent.
    private func taskPage(req: Request) async throws -> Page<TaskResponse> {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)

        var query = Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .with(\.$board)
        if let archived: Bool = req.query["archived"] {
            query = query.filter(\.$isArchived == archived)
        } else {
            query = query.filter(\.$isArchived == false)
        }
        if let boardID: UUID = req.query["boardID"] {
            guard boardIDs.contains(boardID) else {
                throw Abort(.notFound, reason: "The board does not exist.")
            }
            query = query.filter(\.$board.$id == boardID)
        }
        if let status: String = req.query["status"] {
            query = query.filter(\.$statusValue == status)
        }
        if let priority: String = req.query["priority"] {
            query = query.filter(\.$priorityValue == priority)
        }
        if let assigneeID: UUID = req.query["assigneeID"] {
            query = query.filter(\.$assignee.$id == assigneeID)
        }
        if let search = clean(req.query[String.self, at: "q"]) {
            guard search.count <= 120 else {
                throw Abort(.unprocessableEntity, reason: "Search terms cannot exceed 120 characters.")
            }
            query = query.group(.or) { matches in
                matches
                    .filter(\.$title, .custom("LIKE"), "%\(search)%")
                    .filter(\.$description, .custom("LIKE"), "%\(search)%")
                    .filter(\.$publicID == search.lowercased())
            }
        }

        let pageNumber = req.query[Int.self, at: "page"] ?? 1
        let pageSize = req.query[Int.self, at: "per"] ?? 10
        guard pageNumber >= 1, (1...100).contains(pageSize) else {
            throw Abort(
                .unprocessableEntity,
                reason: "Page must be at least 1, and per must contain 1 to 100 items."
            )
        }
        let page = try await query
            .sort(\.$position, .ascending)
            .paginate(PageRequest(page: pageNumber, per: pageSize))
        return try page.map { try TaskResponse(task: $0, boardName: $0.board.name) }
    }

    /// Creates a task at the end of its requested column. The server owns position
    /// assignment so two clients do not need to coordinate index values.
    func create(req: Request) async throws -> Response {
        try CreateTaskRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskRequest.self)

        let userID = try req.auth.require(User.self).requireID()
        let access = try await BoardAccessService.require(
            boardID: input.boardID,
            userID: userID,
            permission: .edit,
            on: req.db
        )

        let status = input.status ?? .backlog
        let priority = input.priority ?? .medium
        try validate(status: status, priority: priority, for: access.board)
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == input.boardID)
            .filter(\.$statusValue == status.rawValue)
            .count()
        let task = Task(
            publicID: try await Task.uniquePublicID(on: req.db),
            boardID: input.boardID,
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: input.description,
            status: status,
            priority: priority,
            position: (count + 1) * 1_000,
            labels: sanitize(labels: input.labels ?? []),
            startAt: input.startAt,
            dueAt: input.dueAt,
            creatorID: userID
        )
        task.properties = sanitize(
            properties: input.properties ?? [:],
            definitions: try await boardDefinitions(boardID: input.boardID, on: req.db)
        )
        task.$assignee.id = try await validAssignee(
            input.assigneeID,
            boardID: input.boardID,
            on: req.db
        )
        try await task.create(on: req.db)

        let response = try TaskResponse(task: task)
        return try await response.encodeResponse(status: .created, for: req)
    }

    /// Updates only fields supplied by the client. A status change also assigns the
    /// task to the end of the destination column so ordering remains valid.
    func update(req: Request) async throws -> TaskResponse {
        let input = try req.content.decode(PatchTaskRequest.self)
        let task = try await findTask(req)
        let board = try await requiredBoard(for: task, on: req.db)
        if case let .value(title) = input.title {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...120).contains(title.count) else {
                throw Abort(.unprocessableEntity, reason: "Use a title between 1 and 120 characters.")
            }
            task.title = title
        } else if case .null = input.title {
            throw Abort(.unprocessableEntity, reason: "Task titles cannot be null.")
        }
        switch input.description {
        case let .value(description):
            guard description.count <= 2_000 else {
                throw Abort(.unprocessableEntity, reason: "Descriptions cannot exceed 2,000 characters.")
            }
            task.description = clean(description)
        case .null:
            task.description = nil
        case .omitted:
            break
        }
        if case let .value(priority) = input.priority {
            guard board.accepts(priority: priority) else {
                throw Abort(.unprocessableEntity, reason: "Select a severity configured for this board.")
            }
            task.priority = priority
        } else if case .null = input.priority {
            throw Abort(.unprocessableEntity, reason: "Task severity cannot be null.")
        }
        if case let .value(labels) = input.labels {
            guard labels.count <= 6 else {
                throw Abort(.unprocessableEntity, reason: "Tasks can have at most six labels.")
            }
            task.labels = sanitize(labels: labels)
        } else if case .null = input.labels {
            task.labels = []
        }
        apply(input.startAt, to: &task.startAt)
        apply(input.dueAt, to: &task.dueAt)
        switch input.properties {
        case let .value(properties):
            task.properties = sanitize(
                properties: properties,
                definitions: try await boardDefinitions(boardID: task.$board.id, on: req.db)
            )
        case .null:
            task.properties = [:]
        case .omitted:
            break
        }
        switch input.assigneeID {
        case let .value(assigneeID):
            task.$assignee.id = try await validAssignee(
                assigneeID,
                boardID: task.$board.id,
                on: req.db
            )
        case .null:
            task.$assignee.id = nil
        case .omitted:
            break
        }
        if case let .value(isArchived) = input.isArchived {
            task.isArchived = isArchived
        } else if case .null = input.isArchived {
            throw Abort(.unprocessableEntity, reason: "Task archive state cannot be null.")
        }
        if case let .value(status) = input.status, status != task.status {
            guard board.accepts(status: status) else {
                throw Abort(.unprocessableEntity, reason: "Select a status configured for this board.")
            }
            let count = try await Task.query(on: req.db)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$statusValue == status.rawValue)
                .count()
            task.status = status
            task.position = (count + 1) * 1_000
        } else if case .null = input.status {
            throw Abort(.unprocessableEntity, reason: "Task status cannot be null.")
        }

        try await task.update(on: req.db)
        return try TaskResponse(task: task)
    }

    /// Moves one task and renumbers both affected columns in a transaction. If any
    /// save fails, Fluent rolls back the full move so clients never see split state.
    func move(req: Request) async throws -> TaskResponse {
        try MoveTaskRequest.validate(content: req)
        let input = try req.content.decode(MoveTaskRequest.self)
        let task = try await findTask(req)
        let board = try await requiredBoard(for: task, on: req.db)
        guard board.accepts(status: input.status) else {
            throw Abort(.unprocessableEntity, reason: "Select a status configured for this board.")
        }
        let taskID = try task.requireID()
        let oldStatus = task.status

        return try await req.db.transaction { database in
            var destination = try await Task.query(on: database)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$statusValue == input.status.rawValue)
                .filter(\.$id != taskID)
                .sort(\.$position, .ascending)
                .all()

            task.status = input.status
            let safeIndex = min(input.targetIndex, destination.count)
            destination.insert(task, at: safeIndex)
            try await normalize(destination, on: database)

            if oldStatus != input.status {
                let source = try await Task.query(on: database)
                    .filter(\.$board.$id == task.$board.id)
                    .filter(\.$statusValue == oldStatus.rawValue)
                    .sort(\.$position, .ascending)
                    .all()
                try await normalize(source, on: database)
            }

            return try TaskResponse(task: task)
        }
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let task = try await findTask(req)
        let taskID = try task.requireID()
        let attachments = try await TaskAttachment.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .all()
        let workspaceActions = WorkspaceActionController()
        try await workspaceActions.deleteStoredAttachments(attachments, for: req)
        try await task.delete(on: req.db)
        workspaceActions.removeLocalAttachmentDirectories(
            boardID: task.$board.id,
            taskID: taskID,
            req: req
        )
        return .noContent
    }

    private func findTask(
        _ req: Request,
        permission: BoardPermission = .edit
    ) async throws -> Task {
        let userID = try req.auth.require(User.self).requireID()
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: userID,
            permission: permission,
            on: req.db
        )
        return task
    }

    private func normalize(_ tasks: [Task], on database: any Database) async throws {
        for (index, task) in tasks.enumerated() {
            task.position = (index + 1) * 1_000
            try await task.save(on: database)
        }
    }

    private func requiredBoard(for task: Task, on database: any Database) async throws -> Board {
        guard let board = try await Board.find(task.$board.id, on: database) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return board
    }

    private func validate(status: TaskStatus, priority: TaskPriority, for board: Board) throws {
        guard board.accepts(status: status), board.accepts(priority: priority) else {
            throw Abort(.unprocessableEntity, reason: "Select a status and severity configured for this board.")
        }
    }

    private func sanitize(labels: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(6))
    }

    private func boardDefinitions(
        boardID: UUID,
        on database: any Database
    ) async throws -> [BoardPropertyDefinition] {
        try await Board.find(boardID, on: database)?.propertyDefinitions ?? []
    }

    private func sanitize(
        properties: [String: String],
        definitions: [BoardPropertyDefinition]
    ) -> [String: String] {
        definitions.reduce(into: [:]) { result, definition in
            if
                let rawValue = properties[definition.id],
                let value = definition.normalizedValue(rawValue)
            {
                result[definition.id] = value
            }
        }
    }

    private func validAssignee(
        _ userID: UUID?,
        boardID: UUID,
        on database: any Database
    ) async throws -> UUID? {
        guard let userID else { return nil }
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: database)
        guard boardIDs.contains(boardID) else {
            throw Abort(.unprocessableEntity, reason: "The assignee cannot access this board.")
        }
        return userID
    }

    private func apply(_ patch: PatchField<Date>.State, to value: inout Date?) {
        switch patch {
        case let .value(date):
            value = date
        case .null:
            value = nil
        case .omitted:
            break
        }
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
