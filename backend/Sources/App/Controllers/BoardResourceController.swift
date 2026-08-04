import Fluent
import Vapor

/// Exposes board-owned collaboration and configuration resources. Member changes,
/// saved-view changes, and template changes require board administrator access.
struct BoardResourceController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let board = routes.grouped("boards", ":boardID")

        let members = board.grouped("members")
        members.get(use: listMembers)
        members.post(use: createMember)
        members.patch(":memberID", use: updateMember)
        members.delete(":memberID", use: deleteMember)

        let views = board.grouped("views")
        views.get(use: listViews)
        views.post(use: createView)
        views.get(":viewID", use: showView)
        views.patch(":viewID", use: updateView)
        views.delete(":viewID", use: deleteView)

        let templates = board.grouped("templates")
        templates.get(use: listTemplates)
        templates.post(use: createTemplate)
        templates.get(":templateID", use: showTemplate)
        templates.patch(":templateID", use: updateTemplate)
        templates.delete(":templateID", use: deleteTemplate)
        templates.post(":templateID", "instantiate", use: instantiateTemplate)
    }

    func listMembers(req: Request) async throws -> [BoardMemberResponse] {
        let access = try await requiredBoard(req, permission: .admin)
        let owner = try await access.board.$owner.get(on: req.db)
        let ownerResponse = try owner.map {
            try BoardMemberResponse(member: nil, user: $0, role: .admin, isOwner: true)
        }
        let members = try await BoardMember.query(on: req.db)
            .filter(\.$board.$id == access.board.requireID())
            .with(\.$user)
            .sort(\.$createdAt, .ascending)
            .all()
        return try [ownerResponse].compactMap { $0 } + members.map {
            try BoardMemberResponse(member: $0, user: $0.user, role: $0.role, isOwner: false)
        }
    }

    func createMember(req: Request) async throws -> Response {
        try CreateBoardMemberRequest.validate(content: req)
        let input = try req.content.decode(CreateBoardMemberRequest.self)
        let access = try await requiredBoard(req, permission: .admin)
        let actor = try req.auth.require(User.self)
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let user = try await User.query(on: req.db).filter(\.$email == email).first() else {
            throw Abort(.unprocessableEntity, reason: "The account does not exist.")
        }
        let boardID = try access.board.requireID()
        let userID = try user.requireID()
        guard access.board.$owner.id != userID else {
            throw Abort(.conflict, reason: "The board owner already has full access.")
        }
        guard try await BoardMember.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$user.$id == userID)
            .first() == nil
        else {
            throw Abort(.conflict, reason: "The user is already a board member.")
        }
        let member = BoardMember(boardID: boardID, userID: userID, role: input.role)
        try await member.create(on: req.db)
        if let configuration = req.application.notificationConfiguration {
            await NotificationService.enqueue(
                try NotificationEvent.boardMemberAdded(
                    member: member,
                    user: user,
                    actor: actor,
                    board: access.board,
                    appURL: configuration.publicAppURL
                ),
                for: req
            )
        }
        return try await BoardMemberResponse(
            member: member,
            user: user,
            role: member.role,
            isOwner: false
        ).encodeResponse(status: .created, for: req)
    }

    func updateMember(req: Request) async throws -> BoardMemberResponse {
        let input = try req.content.decode(UpdateBoardMemberRequest.self)
        let access = try await requiredBoard(req, permission: .admin)
        let member = try await requiredMember(req, boardID: access.board.requireID())
        member.role = input.role
        try await member.update(on: req.db)
        let user = try await member.$user.get(on: req.db)
        return try BoardMemberResponse(
            member: member,
            user: user,
            role: member.role,
            isOwner: false
        )
    }

    func deleteMember(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req, permission: .admin)
        let member = try await requiredMember(req, boardID: access.board.requireID())
        try await member.delete(on: req.db)
        return .noContent
    }

    func listViews(req: Request) async throws -> [BoardViewResponse] {
        let access = try await requiredBoard(req, permission: .view)
        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == access.board.requireID())
            .sort(\.$position, .ascending)
            .all()
        return try views.map(BoardViewResponse.init)
    }

    func showView(req: Request) async throws -> BoardViewResponse {
        let access = try await requiredBoard(req, permission: .view)
        let view = try await requiredView(req, boardID: access.board.requireID())
        return try BoardViewResponse(view: view)
    }

    func createView(req: Request) async throws -> Response {
        try CreateBoardViewRequest.validate(content: req)
        let input = try req.content.decode(CreateBoardViewRequest.self)
        try validate(configuration: input.configuration)
        let access = try await requiredBoard(req, permission: .admin)
        let boardID = try access.board.requireID()
        let count = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .count()
        let view = BoardView(
            boardID: boardID,
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: input.type,
            position: count,
            configuration: input.configuration
        )
        try await view.create(on: req.db)
        return try await BoardViewResponse(view: view)
            .encodeResponse(status: .created, for: req)
    }

    func updateView(req: Request) async throws -> BoardViewResponse {
        let input = try req.content.decode(PatchBoardViewRequest.self)
        let access = try await requiredBoard(req, permission: .admin)
        let view = try await requiredView(req, boardID: access.board.requireID())
        if case let .value(name) = input.name {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...80).contains(name.count) else {
                throw Abort(.unprocessableEntity, reason: "Use a view name between 1 and 80 characters.")
            }
            view.name = name
        } else if case .null = input.name {
            throw Abort(.unprocessableEntity, reason: "View names cannot be null.")
        }
        if case let .value(type) = input.type {
            view.type = type
        } else if case .null = input.type {
            throw Abort(.unprocessableEntity, reason: "View types cannot be null.")
        }
        switch input.configuration {
        case let .value(configuration):
            try validate(configuration: configuration)
            view.configuration = configuration
        case .null:
            view.configuration = nil
        case .omitted:
            break
        }
        try await view.update(on: req.db)
        return try BoardViewResponse(view: view)
    }

    func deleteView(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req, permission: .admin)
        let boardID = try access.board.requireID()
        let view = try await requiredView(req, boardID: boardID)
        let count = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .count()
        guard count > 1 else {
            throw Abort(.unprocessableEntity, reason: "A board must keep at least one view.")
        }
        try await view.delete(on: req.db)
        return .noContent
    }

    func listTemplates(req: Request) async throws -> [TaskTemplateResponse] {
        let access = try await requiredBoard(req, permission: .view)
        let templates = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == access.board.requireID())
            .sort(\.$createdAt, .ascending)
            .all()
        return try templates.map(TaskTemplateResponse.init)
    }

    func showTemplate(req: Request) async throws -> TaskTemplateResponse {
        let access = try await requiredBoard(req, permission: .view)
        let template = try await requiredTemplate(req, boardID: access.board.requireID())
        return try TaskTemplateResponse(template: template)
    }

    func createTemplate(req: Request) async throws -> Response {
        try CreateTaskTemplateRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskTemplateRequest.self)
        let access = try await requiredBoard(req, permission: .admin)
        let status = input.status ?? .backlog
        let priority = input.priority ?? .medium
        try validate(status: status, priority: priority, board: access.board)
        let template = TaskTemplate(
            boardID: try access.board.requireID(),
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: clean(input.description),
            status: status,
            priority: priority,
            labels: sanitize(labels: input.labels ?? []),
            isDefault: input.isDefault ?? false
        )
        try await req.db.transaction { database in
            if template.isDefault {
                try await clearDefaultTemplate(boardID: template.$board.id, on: database)
            }
            try await template.create(on: database)
        }
        return try await TaskTemplateResponse(template: template)
            .encodeResponse(status: .created, for: req)
    }

    func updateTemplate(req: Request) async throws -> TaskTemplateResponse {
        let input = try req.content.decode(PatchTaskTemplateRequest.self)
        let access = try await requiredBoard(req, permission: .admin)
        let template = try await requiredTemplate(req, boardID: access.board.requireID())
        try applyRequiredString(input.name, name: "Template name", limit: 80, to: &template.name)
        try applyRequiredString(input.title, name: "Task title", limit: 120, to: &template.title)
        switch input.description {
        case let .value(description):
            guard description.count <= 5_000 else {
                throw Abort(.unprocessableEntity, reason: "Descriptions cannot exceed 5,000 characters.")
            }
            template.description = clean(description)
        case .null:
            template.description = nil
        case .omitted:
            break
        }
        if case let .value(status) = input.status {
            guard access.board.accepts(status: status) else {
                throw Abort(.unprocessableEntity, reason: "Select a status configured for this board.")
            }
            template.status = status
        } else if case .null = input.status {
            throw Abort(.unprocessableEntity, reason: "Template status cannot be null.")
        }
        if case let .value(priority) = input.priority {
            guard access.board.accepts(priority: priority) else {
                throw Abort(.unprocessableEntity, reason: "Select a severity configured for this board.")
            }
            template.priority = priority
        } else if case .null = input.priority {
            throw Abort(.unprocessableEntity, reason: "Template severity cannot be null.")
        }
        if case let .value(labels) = input.labels {
            guard labels.count <= 6 else {
                throw Abort(.unprocessableEntity, reason: "Templates can have at most six labels.")
            }
            template.labels = sanitize(labels: labels)
        } else if case .null = input.labels {
            template.labels = []
        }
        if case let .value(isDefault) = input.isDefault {
            template.isDefault = isDefault
        } else if case .null = input.isDefault {
            throw Abort(.unprocessableEntity, reason: "Default state cannot be null.")
        }
        try await req.db.transaction { database in
            if template.isDefault {
                try await clearDefaultTemplate(
                    boardID: template.$board.id,
                    except: template.id,
                    on: database
                )
            }
            try await template.update(on: database)
        }
        return try TaskTemplateResponse(template: template)
    }

    func deleteTemplate(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req, permission: .admin)
        let template = try await requiredTemplate(req, boardID: access.board.requireID())
        try await template.delete(on: req.db)
        return .noContent
    }

    /// Creates a normal task from the selected template. The caller becomes the
    /// task creator, and position is assigned at the end of the template's status.
    func instantiateTemplate(req: Request) async throws -> Response {
        let access = try await requiredBoard(req, permission: .edit)
        let boardID = try access.board.requireID()
        let template = try await requiredTemplate(req, boardID: boardID)
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$statusValue == template.status.rawValue)
            .count()
        let task = Task(
            publicID: try await Task.uniquePublicID(on: req.db),
            boardID: boardID,
            title: template.title,
            description: template.description,
            status: template.status,
            priority: template.priority,
            position: (count + 1) * 1_000,
            labels: template.labels,
            creatorID: try req.auth.require(User.self).requireID()
        )
        try await task.create(on: req.db)
        return try await TaskResponse(task: task, boardName: access.board.name)
            .encodeResponse(status: .created, for: req)
    }

    private func requiredBoard(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
    }

    private func requiredMember(_ req: Request, boardID: UUID) async throws -> BoardMember {
        guard
            let memberID = req.parameters.get("memberID", as: UUID.self),
            let member = try await BoardMember.query(on: req.db)
                .filter(\.$id == memberID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The member does not exist.")
        }
        return member
    }

    private func requiredView(_ req: Request, boardID: UUID) async throws -> BoardView {
        guard
            let viewID = req.parameters.get("viewID", as: UUID.self),
            let view = try await BoardView.query(on: req.db)
                .filter(\.$id == viewID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The view does not exist.")
        }
        return view
    }

    private func requiredTemplate(_ req: Request, boardID: UUID) async throws -> TaskTemplate {
        guard
            let templateID = req.parameters.get("templateID", as: UUID.self),
            let template = try await TaskTemplate.query(on: req.db)
                .filter(\.$id == templateID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The template does not exist.")
        }
        return template
    }

    private func validate(configuration: BoardViewConfiguration?) throws {
        guard let configuration else { return }
        guard configuration.filters.count <= 20, configuration.sorts.count <= 10 else {
            throw Abort(.unprocessableEntity, reason: "Views support up to 20 filters and 10 sorts.")
        }
    }

    private func validate(status: TaskStatus, priority: TaskPriority, board: Board) throws {
        guard board.accepts(status: status), board.accepts(priority: priority) else {
            throw Abort(.unprocessableEntity, reason: "Select a status and severity configured for this board.")
        }
    }

    private func applyRequiredString(
        _ patch: PatchField<String>.State,
        name: String,
        limit: Int,
        to value: inout String
    ) throws {
        switch patch {
        case let .value(newValue):
            let newValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...limit).contains(newValue.count) else {
                throw Abort(.unprocessableEntity, reason: "\(name) must contain 1 to \(limit) characters.")
            }
            value = newValue
        case .null:
            throw Abort(.unprocessableEntity, reason: "\(name) cannot be null.")
        case .omitted:
            break
        }
    }

    private func clearDefaultTemplate(
        boardID: UUID,
        except templateID: UUID? = nil,
        on database: any Database
    ) async throws {
        let templates = try await TaskTemplate.query(on: database)
            .filter(\.$board.$id == boardID)
            .all()
        for template in templates where template.id != templateID && template.isDefault {
            template.isDefault = false
            try await template.update(on: database)
        }
    }

    private func sanitize(labels: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(6))
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
