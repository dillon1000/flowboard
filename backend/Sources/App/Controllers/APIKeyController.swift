import Fluent
import Vapor

/// Manages API keys through session-only routes. This prevents a stolen API key
/// from creating a replacement key before the original key is revoked.
struct APIKeyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let keys = routes.grouped("api-keys")
        keys.get(use: list)
        keys.post(use: create)
        keys.delete(":apiKeyID", use: revoke)
    }

    func list(req: Request) async throws -> [APIKeyResponse] {
        let userID = try req.auth.require(User.self).requireID()
        return try await APIKeyCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .all()
            .map(APIKeyResponse.init)
    }

    /// Creates one credential and returns its raw value once. The database keeps
    /// its digest and short prefix, so the user must store the raw value safely.
    func create(req: Request) async throws -> Response {
        try CreateAPIKeyRequest.validate(content: req)
        let input = try req.content.decode(CreateAPIKeyRequest.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "API key name must not be blank.")
        }
        if let expiresAt = input.expiresAt, expiresAt <= Date() {
            throw Abort(.unprocessableEntity, reason: "API key expiry must be in the future.")
        }

        let userID = try req.auth.require(User.self).requireID()
        let generated = APIKeyService.generate()
        let credential = APIKeyCredential(
            userID: userID,
            name: name,
            keyHash: generated.hash,
            keyPrefix: generated.visiblePrefix,
            expiresAt: input.expiresAt
        )
        try await credential.create(on: req.db)
        return try await CreatedAPIKeyResponse(credential: credential, key: generated.raw)
            .encodeResponse(status: .created, for: req)
    }

    /// Revokes one owned key by deleting it. An unknown key and another user's key
    /// both return 404 so the route does not disclose private credential IDs.
    func revoke(req: Request) async throws -> HTTPStatus {
        guard let keyID = req.parameters.get("apiKeyID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid API key ID.")
        }
        let userID = try req.auth.require(User.self).requireID()
        guard let credential = try await APIKeyCredential.query(on: req.db)
            .filter(\.$id == keyID)
            .filter(\.$user.$id == userID)
            .first()
        else {
            throw Abort(.notFound)
        }
        try await credential.delete(on: req.db)
        return .noContent
    }
}
