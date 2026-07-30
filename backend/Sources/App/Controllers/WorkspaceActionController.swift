import Fluent
import Foundation
import Vapor

/// Owns the state-changing browser routes. Each action checks board permissions
/// before changing data and redirects to a stable Leaf page after success.
struct WorkspaceActionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("app", "boards", use: createBoard)
        routes.post("app", "boards", ":boardID", "update", use: updateBoard)
        routes.post("app", "boards", ":boardID", "archive", use: toggleBoardArchive)
        routes.post("app", "boards", ":boardID", "duplicate", use: duplicateBoard)
        routes.post("app", "boards", ":boardID", "delete", use: deleteBoard)
        routes.get("app", "boards", ":boardID", "export", use: exportBoard)
        routes.post("app", "boards", ":boardID", "import", use: importBoard)

        routes.post("app", "boards", ":boardID", "views", use: createView)
        routes.post("app", "boards", ":boardID", "views", ":viewID", "configure", use: configureView)
        routes.post("app", "boards", ":boardID", "properties", use: createProperty)
        routes.post("app", "boards", ":boardID", "members", use: addMember)
        routes.post("app", "boards", ":boardID", "members", ":memberID", "remove", use: removeMember)
        routes.post("app", "boards", ":boardID", "templates", use: createTemplate)

        routes.post("app", "tasks", use: createTask)
        routes.post("app", "tasks", ":taskID", "update", use: updateTask)
        routes.post("app", "tasks", ":taskID", "delete", use: deleteTask)
        routes.post("app", "tasks", ":taskID", "comments", use: createComment)
        routes.post("app", "tasks", ":taskID", "checklist", use: createChecklistItem)
        routes.post("app", "checklist", ":itemID", "toggle", use: toggleChecklistItem)
        routes.post("app", "tasks", ":taskID", "attachments", use: createAttachment)
        routes.get("app", "attachments", ":attachmentID", use: downloadAttachment)

        routes.post("app", "settings", "profile", use: updateProfile)
    }

    func createBoard(req: Request) async throws -> Response {
        let input = try req.content.decode(CreateBoardForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a board name between 2 and 80 characters.")
        }
        let userID = try req.auth.require(User.self).requireID()
        let slug = try await uniqueSlug(slugify(name), on: req.db)
        let board = try await req.db.transaction { database in
            try await WorkspaceService.createBoard(
                name: name,
                slug: slug,
                description: clean(input.description),
                ownerID: userID,
                on: database
            )
        }
        return req.redirect(to: "/app/boards/\(try board.requireID())")
    }

    func updateBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .edit)
        let input = try req.content.decode(UpdateBoardForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a board name between 2 and 80 characters.")
        }
        access.board.name = name
        access.board.description = clean(input.description)
        try await access.board.update(on: req.db)
        return req.redirect(to: "/app/boards/\(try access.board.requireID())/settings")
    }

    func toggleBoardArchive(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        access.board.isArchived.toggle()
        try await access.board.update(on: req.db)
        return req.redirect(
            to: access.board.isArchived
                ? "/app"
                : "/app/boards/\(try access.board.requireID())/settings"
        )
    }

    /// Copies board-owned configuration and tasks in one transaction. Membership
    /// is intentionally excluded so a duplicate starts private to its new owner.
    func duplicateBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .view)
        let userID = try req.auth.require(User.self).requireID()
        let sourceID = try access.board.requireID()
        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .sort(\.$position, .ascending)
            .all()
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .all()
        let templates = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .all()
        let slug = try await uniqueSlug(slugify("\(access.board.name) copy"), on: req.db)

        let duplicate = try await req.db.transaction { database in
            let board = Board(
                name: "\(access.board.name) copy",
                slug: slug,
                description: access.board.description,
                ownerID: userID
            )
            board.propertyDefinitions = access.board.propertyDefinitions
            try await board.create(on: database)
            let boardID = try board.requireID()

            for view in views {
                try await BoardView(
                    boardID: boardID,
                    name: view.name,
                    type: view.type,
                    position: view.position,
                    configuration: view.configuration
                ).create(on: database)
            }
            for source in tasks {
                let task = Task(
                    boardID: boardID,
                    title: source.title,
                    description: source.description,
                    status: source.status,
                    priority: source.priority,
                    position: source.position,
                    labels: source.labels,
                    startAt: source.startAt,
                    dueAt: source.dueAt
                )
                task.properties = source.properties
                try await task.create(on: database)
            }
            for source in templates {
                try await TaskTemplate(
                    boardID: boardID,
                    name: source.name,
                    title: source.title,
                    description: source.description,
                    status: source.status,
                    priority: source.priority,
                    labels: source.labels,
                    isDefault: source.isDefault
                ).create(on: database)
            }
            return board
        }
        return req.redirect(to: "/app/boards/\(try duplicate.requireID())")
    }

    func deleteBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        guard access.isOwner else {
            throw Abort(.forbidden, reason: "Only the board owner can delete this board.")
        }
        let boardID = try access.board.requireID()
        try await access.board.delete(on: req.db)

        // Attachment files are outside SQL, so board deletion removes only the
        // exact board directory after Fluent finishes its cascading deletes.
        let directory = attachmentRoot(req: req) + boardID.uuidString + "/"
        try? FileManager.default.removeItem(atPath: directory)
        return req.redirect(to: "/app")
    }

    func createView(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(CreateViewForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !name.isEmpty,
            let type = BoardViewType(rawValue: input.type.lowercased())
        else {
            throw Abort(.unprocessableEntity, reason: "Choose Board, Table, Calendar, or Gallery.")
        }
        let boardID = try access.board.requireID()
        let count = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .count()
        let view = BoardView(boardID: boardID, name: name, type: type, position: count)
        try await view.create(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/views/\(try view.requireID())")
    }

    func configureView(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let boardID = try access.board.requireID()
        guard
            let viewID = req.parameters.get("viewID", as: UUID.self),
            let view = try await BoardView.query(on: req.db)
                .filter(\.$id == viewID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The view does not exist.")
        }
        let input = try req.content.decode(ConfigureViewForm.self)
        let filters: [BoardViewFilter] = if
            let field = clean(input.filterField),
            let value = clean(input.filterValue)
        {
            [BoardViewFilter(field: field, comparison: "equals", value: value)]
        } else {
            []
        }
        let sorts: [BoardViewSort] = if let field = clean(input.sortField) {
            [BoardViewSort(field: field, direction: input.sortDirection ?? "ascending")]
        } else {
            []
        }
        view.configuration = BoardViewConfiguration(
            groupBy: clean(input.groupBy),
            filters: filters,
            sorts: sorts
        )
        try await view.update(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/views/\(viewID)")
    }

    func createProperty(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(CreatePropertyForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = input.type
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard
            !name.isEmpty,
            let type = BoardPropertyType(rawValue: normalizedType)
        else {
            throw Abort(.unprocessableEntity, reason: "Choose a supported field type.")
        }
        var definitions = access.board.propertyDefinitions ?? []
        definitions.append(
            BoardPropertyDefinition(
                id: UUID().uuidString.lowercased(),
                name: name,
                type: type,
                options: []
            )
        )
        access.board.propertyDefinitions = definitions
        try await access.board.update(on: req.db)
        return req.redirect(to: "/app/boards/\(try access.board.requireID())/settings")
    }

    func addMember(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(AddMemberForm.self)
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard
            let role = BoardMemberRole(rawValue: input.role.lowercased()),
            let user = try await User.query(on: req.db).filter(\.$email == email).first()
        else {
            throw Abort(.unprocessableEntity, reason: "The account or role does not exist.")
        }
        let boardID = try access.board.requireID()
        let userID = try user.requireID()
        guard access.board.$owner.id != userID else {
            throw Abort(.unprocessableEntity, reason: "The board owner already has full access.")
        }
        if let existing = try await BoardMember.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$user.$id == userID)
            .first()
        {
            existing.role = role
            try await existing.update(on: req.db)
        } else {
            try await BoardMember(boardID: boardID, userID: userID, role: role).create(on: req.db)
        }
        return req.redirect(to: "/app/boards/\(boardID)/settings")
    }

    func removeMember(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let boardID = try access.board.requireID()
        guard
            let memberID = req.parameters.get("memberID", as: UUID.self),
            let member = try await BoardMember.query(on: req.db)
                .filter(\.$id == memberID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The member does not exist.")
        }
        try await member.delete(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/settings")
    }

    func createTemplate(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(CreateTemplateForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Template name and task title are required.")
        }
        try await TaskTemplate(
            boardID: access.board.requireID(),
            name: name,
            title: title
        ).create(on: req.db)
        return req.redirect(to: "/app/boards/\(try access.board.requireID())/settings")
    }

    func createTask(req: Request) async throws -> Response {
        let input = try req.content.decode(CreateTaskForm.self)
        let userID = try req.auth.require(User.self).requireID()
        _ = try await BoardAccessService.require(
            boardID: input.boardID,
            userID: userID,
            permission: .edit,
            on: req.db
        )
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Task title is required.")
        }
        let status = TaskStatus(rawValue: input.status ?? "") ?? .backlog
        let priority = TaskPriority(rawValue: input.priority ?? "") ?? .medium
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == input.boardID)
            .filter(\.$status == status)
            .count()
        let task = Task(
            boardID: input.boardID,
            title: title,
            description: clean(input.description),
            status: status,
            priority: priority,
            position: (count + 1) * 1_000,
            labels: labels(input.labels),
            startAt: parseDate(input.startAt),
            dueAt: parseDate(input.dueAt)
        )
        try await task.create(on: req.db)
        return req.redirect(to: safeReturn(input.returnTo, fallback: "/app/tasks/\(try task.requireID())"))
    }

    func updateTask(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(UpdateTaskForm.self)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !title.isEmpty,
            let status = TaskStatus(rawValue: input.status),
            let priority = TaskPriority(rawValue: input.priority)
        else {
            throw Abort(.unprocessableEntity, reason: "Task title, status, and priority are required.")
        }
        task.title = title
        task.description = clean(input.description)
        task.priority = priority
        task.labels = labels(input.labels)
        task.startAt = parseDate(input.startAt)
        task.dueAt = parseDate(input.dueAt)
        if task.status != status {
            let count = try await Task.query(on: req.db)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$status == status)
                .count()
            task.status = status
            task.position = (count + 1) * 1_000
        }
        if let assignee = clean(input.assigneeID).flatMap(UUID.init(uuidString:)) {
            let memberIDs = try await BoardAccessService.boardIDs(for: assignee, on: req.db)
            task.$assignee.id = memberIDs.contains(task.$board.id) ? assignee : nil
        } else {
            task.$assignee.id = nil
        }
        try await task.update(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func deleteTask(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let boardID = task.$board.id
        let taskID = try task.requireID()
        try await task.delete(on: req.db)
        try? FileManager.default.removeItem(
            atPath: attachmentRoot(req: req) + boardID.uuidString + "/" + taskID.uuidString
        )
        return req.redirect(to: "/app/boards/\(boardID)")
    }

    func createComment(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .comment)
        let input = try req.content.decode(CommentForm.self)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 4_000 else {
            throw Abort(.unprocessableEntity, reason: "Use a comment between 1 and 4,000 characters.")
        }
        try await TaskComment(
            taskID: task.requireID(),
            authorID: req.auth.require(User.self).requireID(),
            body: body
        ).create(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func createChecklistItem(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(ChecklistForm.self)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else {
            throw Abort(.unprocessableEntity, reason: "Use a checklist title between 1 and 200 characters.")
        }
        let taskID = try task.requireID()
        let count = try await ChecklistItem.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .count()
        try await ChecklistItem(taskID: taskID, title: title, position: count).create(on: req.db)
        return req.redirect(to: "/app/tasks/\(taskID)")
    }

    func toggleChecklistItem(req: Request) async throws -> Response {
        guard
            let itemID = req.parameters.get("itemID", as: UUID.self),
            let item = try await ChecklistItem.find(itemID, on: req.db),
            let task = try await Task.find(item.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The checklist item does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: .edit, for: req)
        item.isCompleted.toggle()
        try await item.update(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func createAttachment(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(AttachmentForm.self)
        guard input.file.data.readableBytes <= 10_000_000 else {
            throw Abort(.payloadTooLarge, reason: "Attachments must be 10 MB or smaller.")
        }
        let boardID = task.$board.id
        let taskID = try task.requireID()
        let fileExtension = input.file.extension?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let storageName = UUID().uuidString + (fileExtension.map { ".\($0)" } ?? "")
        let directory = attachmentRoot(req: req)
            + boardID.uuidString + "/" + taskID.uuidString + "/"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        try await req.fileio.writeFile(input.file.data, at: directory + storageName)

        let attachment = TaskAttachment(
            taskID: taskID,
            uploadedByID: try req.auth.require(User.self).requireID(),
            fileName: safeFileName(input.file.filename),
            storageName: storageName,
            contentType: input.file.contentType?.serialize() ?? "application/octet-stream",
            byteCount: input.file.data.readableBytes
        )
        do {
            try await attachment.create(on: req.db)
        } catch {
            try? FileManager.default.removeItem(atPath: directory + storageName)
            throw error
        }
        return req.redirect(to: "/app/tasks/\(taskID)")
    }

    func downloadAttachment(req: Request) async throws -> Response {
        guard
            let attachmentID = req.parameters.get("attachmentID", as: UUID.self),
            let attachment = try await TaskAttachment.find(attachmentID, on: req.db),
            let task = try await Task.find(attachment.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The attachment does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: .view, for: req)
        let path = attachmentRoot(req: req)
            + task.$board.id.uuidString + "/"
            + (try task.requireID()).uuidString + "/"
            + attachment.storageName
        let response = try await req.fileio.asyncStreamFile(at: path)
        response.headers.contentDisposition = .init(.attachment, filename: attachment.fileName)
        if let mediaType = attachment.fileName
            .split(separator: ".")
            .last
            .flatMap({ HTTPMediaType.fileExtension(String($0)) })
        {
            response.headers.contentType = mediaType
        }
        return response
    }

    func updateProfile(req: Request) async throws -> Response {
        let input = try req.content.decode(UpdateProfileRequest.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a name between 2 and 80 characters.")
        }
        let user = try req.auth.require(User.self)
        user.name = name
        try await user.update(on: req.db)
        return req.redirect(to: "/app/settings")
    }

    func exportBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .view)
        let boardID = try access.board.requireID()
        let tasks = try await Task.query(on: req.db).filter(\.$board.$id == boardID).all()
        let views = try await BoardView.query(on: req.db).filter(\.$board.$id == boardID).all()
        let templates = try await TaskTemplate.query(on: req.db).filter(\.$board.$id == boardID).all()
        let payload = BoardExport(
            version: 1,
            name: access.board.name,
            description: access.board.description,
            propertyDefinitions: access.board.propertyDefinitions ?? [],
            views: views.map {
                ExportView(name: $0.name, type: $0.type, position: $0.position, configuration: $0.configuration)
            },
            tasks: tasks.map {
                ExportTask(
                    title: $0.title,
                    description: $0.description,
                    status: $0.status,
                    priority: $0.priority,
                    position: $0.position,
                    labels: $0.labels,
                    startAt: $0.startAt,
                    dueAt: $0.dueAt,
                    properties: $0.properties
                )
            },
            templates: templates.map {
                ExportTemplate(
                    name: $0.name,
                    title: $0.title,
                    description: $0.description,
                    status: $0.status,
                    priority: $0.priority,
                    labels: $0.labels,
                    isDefault: $0.isDefault
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        response.headers.contentDisposition = .init(
            .attachment,
            filename: "\(access.board.slug).json"
        )
        return response
    }

    func importBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(ImportForm.self)
        guard input.file.data.readableBytes <= 2_000_000 else {
            throw Abort(.payloadTooLarge, reason: "Board imports must be 2 MB or smaller.")
        }
        guard let data = input.file.data.getData(
            at: input.file.data.readerIndex,
            length: input.file.data.readableBytes
        ) else {
            throw Abort(.badRequest, reason: "The import file could not be read.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BoardExport.self, from: data)
        guard payload.version == 1, payload.tasks.count <= 5_000 else {
            throw Abort(.unprocessableEntity, reason: "This board export is not supported.")
        }
        let boardID = try access.board.requireID()
        try await req.db.transaction { database in
            for exported in payload.tasks {
                let task = Task(
                    boardID: boardID,
                    title: String(exported.title.prefix(120)),
                    description: exported.description,
                    status: exported.status,
                    priority: exported.priority,
                    position: exported.position,
                    labels: Array(exported.labels.prefix(6)),
                    startAt: exported.startAt,
                    dueAt: exported.dueAt
                )
                task.properties = exported.properties
                try await task.create(on: database)
            }
        }
        return req.redirect(to: "/app/boards/\(boardID)")
    }

    private func requiredBoard(
        for req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await requireAccess(boardID: boardID, permission: permission, for: req)
    }

    private func requiredTask(
        for req: Request,
        permission: BoardPermission
    ) async throws -> Task {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: permission, for: req)
        return task
    }

    private func requireAccess(
        boardID: UUID,
        permission: BoardPermission,
        for req: Request
    ) async throws -> BoardAccess {
        try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
    }

    private func uniqueSlug(_ requested: String, on database: any Database) async throws -> String {
        guard try await Board.query(on: database).filter(\.$slug == requested).first() != nil else {
            return requested
        }
        return "\(String(requested.prefix(39)))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func slugify(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "board" : normalized).prefix(48))
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func labels(_ value: String?) -> [String] {
        Array(
            (value ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(6)
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = clean(value) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: 12
            )
        )
    }

    private func safeReturn(_ value: String?, fallback: String) -> String {
        guard let value, value.hasPrefix("/app/"), !value.hasPrefix("//") else {
            return fallback
        }
        return value
    }

    private func safeFileName(_ value: String) -> String {
        String(
            value
                .split(whereSeparator: { $0 == "/" || $0 == "\\" })
                .last
                .map(String.init)?
                .prefix(160)
                ?? "attachment"
        )
    }

    private func attachmentRoot(req: Request) -> String {
        req.application.directory.workingDirectory + "Uploads/"
    }
}

private struct CreateBoardForm: Content {
    let name: String
    let description: String?
}

private struct UpdateBoardForm: Content {
    let name: String
    let description: String?
}

private struct CreateViewForm: Content {
    let name: String
    let type: String
}

private struct ConfigureViewForm: Content {
    let groupBy: String?
    let filterField: String?
    let filterValue: String?
    let sortField: String?
    let sortDirection: String?
}

private struct CreatePropertyForm: Content {
    let name: String
    let type: String
}

private struct AddMemberForm: Content {
    let email: String
    let role: String
}

private struct CreateTemplateForm: Content {
    let name: String
    let title: String
}

private struct CreateTaskForm: Content {
    let boardID: UUID
    let title: String
    let description: String?
    let status: String?
    let priority: String?
    let labels: String?
    let startAt: String?
    let dueAt: String?
    let returnTo: String?
}

private struct UpdateTaskForm: Content {
    let title: String
    let description: String?
    let status: String
    let priority: String
    let labels: String?
    let startAt: String?
    let dueAt: String?
    let assigneeID: String?
}

private struct CommentForm: Content {
    let body: String
}

private struct ChecklistForm: Content {
    let title: String
}

private struct AttachmentForm: Content {
    let file: File
}

private struct ImportForm: Content {
    let file: File
}

private struct BoardExport: Codable {
    let version: Int
    let name: String
    let description: String?
    let propertyDefinitions: [BoardPropertyDefinition]
    let views: [ExportView]
    let tasks: [ExportTask]
    let templates: [ExportTemplate]
}

private struct ExportView: Codable {
    let name: String
    let type: BoardViewType
    let position: Int
    let configuration: BoardViewConfiguration?
}

private struct ExportTask: Codable {
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let position: Int
    let labels: [String]
    let startAt: Date?
    let dueAt: Date?
    let properties: [String: String]?
}

private struct ExportTemplate: Codable {
    let name: String
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let labels: [String]
    let isDefault: Bool
}
