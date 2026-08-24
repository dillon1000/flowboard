import Fluent
import Foundation
import Vapor

struct ConnectedAppsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.delete(":clientID", use: disconnect)
    }

    func disconnect(req: Request) async throws -> HTTPStatus {
        guard let clientID = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The connected app does not exist.")
        }
        let userID = try req.auth.require(User.self).requireID()
        let tokens = try await MCPOAuthToken.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$client.$id == clientID)
            .all()
        guard !tokens.isEmpty else {
            throw Abort(.notFound, reason: "The connected app does not exist.")
        }
        try await tokens.delete(on: req.db)
        try await MCPOAuthAuthorizationCode.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$client.$id == clientID)
            .delete()
        return .noContent
    }
}
