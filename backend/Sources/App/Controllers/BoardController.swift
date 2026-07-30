import Fluent
import Vapor

struct BoardController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards")
        boards.get(use: index)
        boards.get("default", use: showDefault)
        boards.get(":boardID", use: show)
        boards.post(use: create)
    }

    func index(req: Request) async throws -> [BoardResponse] {
        let boards = try await Board.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .all()
        return try boards.map(BoardResponse.init)
    }

    func showDefault(req: Request) async throws -> BoardResponse {
        guard let board = try await Board.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .first()
        else {
            throw Abort(.notFound, reason: "No board exists.")
        }

        return try await response(for: board, on: req.db)
    }

    func show(req: Request) async throws -> BoardResponse {
        guard
            let boardID = req.parameters.get("boardID", as: UUID.self),
            let board = try await Board.find(boardID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }

        return try await response(for: board, on: req.db)
    }

    /// Validates the public DTO before it creates a persisted board. A unique slug
    /// conflict returns a stable client error instead of exposing a database error.
    func create(req: Request) async throws -> Response {
        try CreateBoardRequest.validate(content: req)
        let input = try req.content.decode(CreateBoardRequest.self)

        let exists = try await Board.query(on: req.db)
            .filter(\.$slug == input.slug.lowercased())
            .first() != nil
        guard !exists else {
            throw Abort(.conflict, reason: "A board with this slug already exists.")
        }

        let board = Board(name: input.name, slug: input.slug.lowercased())
        try await board.create(on: req.db)

        let response = try BoardResponse(board: board)
        return try await response.encodeResponse(status: .created, for: req)
    }

    private func response(for board: Board, on database: any Database) async throws -> BoardResponse {
        let boardID = try board.requireID()
        let tasks = try await Task.query(on: database)
            .filter(\.$board.$id == boardID)
            .all()
        return try BoardResponse(board: board, tasks: tasks)
    }
}
