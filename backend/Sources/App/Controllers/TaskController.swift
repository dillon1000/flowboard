import Fluent
import Vapor

struct TaskController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let tasks = routes.grouped("tasks")
        tasks.get(use: index)
        tasks.post(use: create)
        tasks.patch(":taskID", use: update)
        tasks.post(":taskID", "move", use: move)
        tasks.delete(":taskID", use: delete)
    }

    func index(req: Request) async throws -> Page<TaskResponse> {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)

        var query = Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .with(\.$board)
        if let boardID: UUID = req.query["boardID"] {
            guard boardIDs.contains(boardID) else {
                throw Abort(.notFound, reason: "The board does not exist.")
            }
            query = query.filter(\.$board.$id == boardID)
        }
        if let status: TaskStatus = req.query["status"] {
            query = query.filter(\.$status == status)
        }

        let page = try await query.sort(\.$position, .ascending).paginate(for: req)
        return try page.map { try TaskResponse(task: $0, boardName: $0.board.name) }
    }

    /// Creates a task at the end of its requested column. The server owns position
    /// assignment so two clients do not need to coordinate index values.
    func create(req: Request) async throws -> Response {
        try CreateTaskRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskRequest.self)

        let userID = try req.auth.require(User.self).requireID()
        _ = try await BoardAccessService.require(
            boardID: input.boardID,
            userID: userID,
            permission: .edit,
            on: req.db
        )

        let status = input.status ?? .backlog
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == input.boardID)
            .filter(\.$status == status)
            .count()
        let task = Task(
            boardID: input.boardID,
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: input.description,
            status: status,
            priority: input.priority ?? .medium,
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

    /// Replaces the editable task fields. Moving between columns also assigns the task
    /// to the end of the destination column, which keeps ordering valid for API clients.
    func update(req: Request) async throws -> TaskResponse {
        try UpdateTaskRequest.validate(content: req)
        let input = try req.content.decode(UpdateTaskRequest.self)
        let task = try await findTask(req)

        task.title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.description = input.description
        task.priority = input.priority
        task.labels = sanitize(labels: input.labels)
        task.startAt = input.startAt
        task.dueAt = input.dueAt
        task.properties = sanitize(
            properties: input.properties ?? [:],
            definitions: try await boardDefinitions(boardID: task.$board.id, on: req.db)
        )
        task.$assignee.id = try await validAssignee(
            input.assigneeID,
            boardID: task.$board.id,
            on: req.db
        )
        if input.status != task.status {
            let count = try await Task.query(on: req.db)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$status == input.status)
                .count()
            task.status = input.status
            task.position = (count + 1) * 1_000
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
        let taskID = try task.requireID()
        let oldStatus = task.status

        return try await req.db.transaction { database in
            var destination = try await Task.query(on: database)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$status == input.status)
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
                    .filter(\.$status == oldStatus)
                    .sort(\.$position, .ascending)
                    .all()
                try await normalize(source, on: database)
            }

            return try TaskResponse(task: task)
        }
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let task = try await findTask(req)
        try await task.delete(on: req.db)
        return .noContent
    }

    private func findTask(_ req: Request) async throws -> Task {
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
            permission: .edit,
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

    private func sanitize(labels: [String]) -> [String] {
        Array(
            labels
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(6)
        )
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
        let allowed = Set(definitions.map(\.id))
        return properties.reduce(into: [:]) { result, entry in
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if allowed.contains(entry.key), !value.isEmpty {
                result[entry.key] = String(value.prefix(2_000))
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
}
