import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
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
            board.statusDefinitions = access.board.taskStatuses
            board.severityDefinitions = access.board.taskSeverities
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
                    dueAt: source.dueAt,
                    creatorID: userID
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
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .with(\.$attachments)
            .all()
        try await deleteStoredAttachments(
            tasks.flatMap { $0.attachments },
            for: req
        )
        try await access.board.delete(on: req.db)

        removeLocalAttachmentDirectories(boardID: boardID, req: req)
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
        let groupBy = ["status", "priority"].contains(input.groupBy ?? "")
            ? input.groupBy
            : "status"
        let sortDirection = input.sortDirection == "descending" ? "descending" : "ascending"
        view.configuration = BoardViewConfiguration(
            groupBy: groupBy,
            filters: filters,
            sorts: sorts.map { BoardViewSort(field: $0.field, direction: sortDirection) }
        )
        try await view.update(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/views/\(viewID)")
    }

    func deleteView(req: Request) async throws -> Response {
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
        let count = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .count()
        guard count > 1 else {
            throw Abort(.unprocessableEntity, reason: "A board must keep at least one view.")
        }
        try await view.delete(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/settings")
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
            (1...60).contains(name.count),
            let type = BoardPropertyType(rawValue: normalizedType)
        else {
            throw Abort(.unprocessableEntity, reason: "Choose a supported field type.")
        }
        let optionNames = (input.options ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if type.usesOptions {
            guard
                (1...20).contains(optionNames.count),
                optionNames.allSatisfy({ (1...40).contains($0.count) }),
                Set(optionNames.map { $0.lowercased() }).count == optionNames.count
            else {
                throw Abort(
                    .unprocessableEntity,
                    reason: "Add 1 to 20 unique options, each no longer than 40 characters."
                )
            }
        }
        let palette = BoardTaskOptionColor.presetPalette
        var usedOptionIDs: Set<String> = []
        let options: [BoardPropertyOption] = if type.usesOptions {
            optionNames.enumerated().map { index, optionName in
                let baseID = String(slugify(optionName).prefix(32))
                var optionID = baseID
                var suffix = 2
                while usedOptionIDs.contains(optionID) {
                    optionID = "\(String(baseID.prefix(28)))-\(suffix)"
                    suffix += 1
                }
                usedOptionIDs.insert(optionID)
                return BoardPropertyOption(
                    id: optionID,
                    name: optionName,
                    color: palette[index % palette.count].rawValue
                )
            }
        } else {
            []
        }
        var definitions = access.board.propertyDefinitions ?? []
        definitions.append(
            BoardPropertyDefinition(
                id: UUID().uuidString.lowercased(),
                name: name,
                type: type,
                options: options
            )
        )
        access.board.propertyDefinitions = definitions
        try await access.board.update(on: req.db)
        return req.redirect(to: "/app/boards/\(try access.board.requireID())/settings")
    }

    /// Adds one ordered status or severity definition to a board. The generated
    /// ID becomes the stored task value, so later label changes can remain safe.
    func createTaskOption(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let input = try req.content.decode(CreateTaskOptionForm.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            (1...40).contains(name.count),
            let color = BoardTaskOptionColor(rawValue: input.color)
        else {
            throw Abort(.unprocessableEntity, reason: "Use a name between 1 and 40 characters and select a color.")
        }

        let isStatus = input.kind == "status"
        guard isStatus || input.kind == "severity" else {
            throw Abort(.unprocessableEntity, reason: "Choose status or severity.")
        }
        var options = isStatus ? access.board.taskStatuses : access.board.taskSeverities
        guard options.count < 12 else {
            throw Abort(.unprocessableEntity, reason: "A board can have up to 12 values of each type.")
        }
        guard !options.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw Abort(.unprocessableEntity, reason: "That name already exists on this board.")
        }

        let baseID = String(slugify(name).prefix(32))
        var optionID = baseID
        var suffix = 2
        while options.contains(where: { $0.id == optionID }) {
            optionID = "\(String(baseID.prefix(28)))-\(suffix)"
            suffix += 1
        }
        options.append(
            BoardTaskOption(
                id: optionID,
                name: name,
                color: color,
                isCompleted: isStatus && input.isCompleted != nil
            )
        )
        if isStatus {
            access.board.statusDefinitions = options
        } else {
            access.board.severityDefinitions = options
        }
        try await access.board.update(on: req.db)
        return req.redirect(to: "/app/boards/\(try access.board.requireID())/settings#workflow")
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

    func useTemplate(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .edit)
        let userID = try req.auth.require(User.self).requireID()
        let boardID = try access.board.requireID()
        let template = try await requiredTemplate(for: req, boardID: boardID)
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$statusValue == template.status.rawValue)
            .count()
        let task = Task(
            boardID: boardID,
            title: template.title,
            description: template.description,
            status: template.status,
            priority: template.priority,
            position: (count + 1) * 1_000,
            labels: template.labels,
            creatorID: userID
        )
        try await task.create(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func setDefaultTemplate(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let boardID = try access.board.requireID()
        let selected = try await requiredTemplate(for: req, boardID: boardID)
        let templates = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .all()
        for template in templates {
            template.isDefault = template.id == selected.id
            try await template.update(on: req.db)
        }
        return req.redirect(to: "/app/boards/\(boardID)/settings")
    }

    func deleteTemplate(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let boardID = try access.board.requireID()
        let template = try await requiredTemplate(for: req, boardID: boardID)
        try await template.delete(on: req.db)
        return req.redirect(to: "/app/boards/\(boardID)/settings")
    }
}
