import Fluent
import Vapor

/// Manages Canvas connections through browser-session authentication only.
struct CanvasConnectionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let connections = routes.grouped("canvas-connections")
        connections.get(use: list)
        connections.post(use: create)
        connections.post(":connectionID", "rotate", use: rotate)
        connections.delete(":connectionID", use: disconnect)
    }

    func list(req: Request) async throws -> [CanvasConnectionResponse] {
        let userID = try req.auth.require(User.self).requireID()
        return try await CanvasConnection.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .ascending)
            .all()
            .map(CanvasConnectionResponse.init)
    }

    func create(req: Request) async throws -> Response {
        let input = try req.content.decode(CreateCanvasConnectionRequest.self)
        let created = try await CanvasCredentialService.create(
            canvasOrigin: input.canvasOrigin,
            userID: req.auth.require(User.self).requireID(),
            on: req.db
        )
        return try await CreatedCanvasConnectionResponse(
            connection: created.connection,
            syncKey: created.raw
        ).encodeResponse(status: .created, for: req)
    }

    func rotate(req: Request) async throws -> CreatedCanvasConnectionResponse {
        let connection = try await ownedConnection(req)
        let raw = try await CanvasCredentialService.rotate(connection: connection, on: req.db)
        return try CreatedCanvasConnectionResponse(connection: connection, syncKey: raw)
    }

    func disconnect(req: Request) async throws -> HTTPStatus {
        let connection = try await ownedConnection(req)
        try await connection.delete(on: req.db)
        return .noContent
    }

    private func ownedConnection(_ req: Request) async throws -> CanvasConnection {
        guard let connectionID = req.parameters.get("connectionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid Canvas connection ID.")
        }
        let userID = try req.auth.require(User.self).requireID()
        guard let connection = try await CanvasConnection.query(on: req.db)
            .filter(\.$id == connectionID)
            .filter(\.$user.$id == userID)
            .first()
        else {
            throw Abort(.notFound)
        }
        return connection
    }
}
