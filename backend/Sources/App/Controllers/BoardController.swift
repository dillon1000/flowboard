import Fluent
import Foundation
import Vapor

struct BoardController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards")
        boards.get(use: index)
        boards.get("default", use: showDefault)
        boards.get(":boardID", use: show)
        boards.post(use: create)
        boards.patch(":boardID", use: update)
        boards.delete(":boardID", use: delete)
    }

    func index(req: Request) async throws -> [BoardSummaryResponse] {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        var query = Board.query(on: req.db)
            .filter(\.$id ~~ boardIDs)
            .with(\.$tasks)
        if let archived: Bool = req.query["archived"] {
            query = query.filter(\.$isArchived == archived)
        }
        if let search = clean(req.query[String.self, at: "q"]) {
            guard search.count <= 120 else {
                throw Abort(.unprocessableEntity, reason: "Search terms cannot exceed 120 characters.")
            }
            query = query.group(.or) { matches in
                matches
                    .filter(\.$name, .custom("LIKE"), "%\(search)%")
                    .filter(\.$description, .custom("LIKE"), "%\(search)%")
                    .filter(\.$slug, .custom("LIKE"), "%\(search)%")
            }
        }
        let boards = try await query.sort(\.$createdAt, .ascending).all()
        return try boards.map { try BoardSummaryResponse(board: $0, tasks: $0.tasks) }
    }

    func showDefault(req: Request) async throws -> BoardResponse {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        guard let board = try await Board.query(on: req.db)
            .filter(\.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .sort(\.$createdAt, .ascending)
            .first()
        else {
            throw Abort(.notFound, reason: "Create a board to get started.")
        }
        return try await response(for: board, on: req.db)
    }

    func show(req: Request) async throws -> BoardResponse {
        let board = try await findBoard(req)
        return try await response(for: board, on: req.db)
    }

    /// Creates a user-owned board. The optional user slug is normalized, and a short
    /// suffix is added only when another board already uses that URL.
    func create(req: Request) async throws -> Response {
        try CreateBoardRequest.validate(content: req)
        let input = try req.content.decode(CreateBoardRequest.self)
        let userID = try req.auth.require(User.self).requireID()
        let requestedSlug = slugify(input.slug ?? input.name)
        let slug = try await uniqueSlug(requestedSlug, on: req.db)

        let board = try await req.db.transaction { database in
            try await WorkspaceService.createBoard(
                name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
                slug: slug,
                description: input.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                ownerID: userID,
                on: database
            )
        }

        return try await BoardResponse(board: board)
            .encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> BoardResponse {
        let input = try req.content.decode(PatchBoardRequest.self)
        let permission: BoardPermission = switch input.isArchived {
        case .omitted:
            .edit
        case .null, .value:
            .admin
        }
        let board = try await findBoard(req, permission: permission)
        let canvasLink = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id == board.requireID())
            .first()
        if canvasLink != nil, input.name.isSupplied {
            throw Abort(.conflict, reason: "Canvas manages the name of this linked course.")
        }
        if case let .value(name) = input.name {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...80).contains(name.count) else {
                throw Abort(.unprocessableEntity, reason: "Use a board name between 2 and 80 characters.")
            }
            board.name = name
        } else if case .null = input.name {
            throw Abort(.unprocessableEntity, reason: "Board names cannot be null.")
        }
        switch input.description {
        case let .value(description):
            guard description.count <= 500 else {
                throw Abort(.unprocessableEntity, reason: "Descriptions cannot exceed 500 characters.")
            }
            board.description = clean(description)
        case .null:
            board.description = nil
        case .omitted:
            break
        }
        if case let .value(isArchived) = input.isArchived {
            board.isArchived = isArchived
        } else if case .null = input.isArchived {
            throw Abort(.unprocessableEntity, reason: "Board archive state cannot be null.")
        }
        try await req.db.transaction { database in
            try await board.update(on: database)
            if input.isArchived.isSupplied, let canvasLink {
                // An explicit local archive choice becomes authoritative until Canvas
                // reaches the missing-item threshold again.
                canvasLink.syncArchived = false
                try await canvasLink.update(on: database)
            }
        }
        return try await response(for: board, on: req.db)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let access = try await findAccess(req, permission: .admin)
        guard access.isOwner else {
            throw Abort(.forbidden, reason: "Only the board owner can delete this board.")
        }
        let board = access.board
        let boardID = try board.requireID()
        let isCanvasLinked = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .first() != nil
        guard !isCanvasLinked else {
            throw Abort(
                .conflict,
                reason: "Disconnect the Canvas connection before deleting this linked course."
            )
        }
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .with(\.$attachments)
            .all()
        try await AttachmentStorageService.delete(tasks.flatMap(\.attachments), for: req)
        try await board.delete(on: req.db)
        AttachmentStorageService.removeLocalDirectories(boardID: boardID, req: req)
        return .noContent
    }

    private func findBoard(
        _ req: Request,
        permission: BoardPermission = .view
    ) async throws -> Board {
        try await findAccess(req, permission: permission).board
    }

    private func findAccess(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        let userID = try req.auth.require(User.self).requireID()
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: userID,
            permission: permission,
            on: req.db
        )
    }

    private func response(for board: Board, on database: any Database) async throws -> BoardResponse {
        let boardID = try board.requireID()
        let tasks = try await Task.query(on: database)
            .filter(\.$board.$id == boardID)
            .all()
        return try BoardResponse(board: board, tasks: tasks)
    }

    private func slugify(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "board" : normalized).prefix(48))
    }

    private func uniqueSlug(_ requested: String, on database: any Database) async throws -> String {
        guard try await Board.query(on: database).filter(\.$slug == requested).first() != nil else {
            return requested
        }
        return "\(String(requested.prefix(39)))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
