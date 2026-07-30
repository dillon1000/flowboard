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
        let boards = try await Board.query(on: req.db)
            .filter(\.$owner.$id == userID)
            .with(\.$tasks)
            .sort(\.$createdAt, .ascending)
            .all()
        return try boards.map { try BoardSummaryResponse(board: $0, tasks: $0.tasks) }
    }

    func showDefault(req: Request) async throws -> BoardResponse {
        let userID = try req.auth.require(User.self).requireID()
        guard let board = try await Board.query(on: req.db)
            .filter(\.$owner.$id == userID)
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

        let board = Board(
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
            slug: slug,
            ownerID: userID
        )
        try await board.create(on: req.db)

        return try await BoardResponse(board: board)
            .encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> BoardResponse {
        try UpdateBoardRequest.validate(content: req)
        let input = try req.content.decode(UpdateBoardRequest.self)
        let board = try await findBoard(req)
        board.name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await board.update(on: req.db)
        return try await response(for: board, on: req.db)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let board = try await findBoard(req)
        try await board.delete(on: req.db)
        return .noContent
    }

    private func findBoard(_ req: Request) async throws -> Board {
        let userID = try req.auth.require(User.self).requireID()
        guard
            let boardID = req.parameters.get("boardID", as: UUID.self),
            let board = try await Board.query(on: req.db)
                .filter(\.$id == boardID)
                .filter(\.$owner.$id == userID)
                .first()
        else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return board
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
}
