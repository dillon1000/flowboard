import Fluent
import Vapor

extension WorkspaceActionController {
    /// Creates one key and renders its secret directly. The form bypasses Turbo,
    /// so no redirect, URL, or session stores the raw value.
    func createAPIKey(req: Request) async throws -> Response {
        let created: (credential: APIKeyCredential, raw: String)
        do {
            let input = try req.content.decode(CreateAPIKeyForm.self)
            let userID = try req.auth.require(User.self).requireID()
            created = try await APIKeyService.create(
                name: input.name,
                expiresAt: nil,
                userID: userID,
                on: req.db
            )
        } catch {
            let message = (error as? any AbortError)?.reason
                ?? "The API key could not be created. Try again."
            let page = try await AppPageController().renderAPIKeysPage(
                for: req,
                error: message
            )
            return try await page.encodeResponse(status: .unprocessableEntity, for: req)
        }

        do {
            let page = try await AppPageController().renderAPIKeysPage(
                for: req,
                createdKey: created.raw
            )
            let response = try await page.encodeResponse(status: .created, for: req)
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return response
        } catch {
            // Revoke a key whose secret could not be shown. The user could not
            // recover that value, so leaving the key active would create dead state.
            try? await created.credential.delete(on: req.db)
            throw error
        }
    }

    /// Revokes only a key owned by the current user. A missing or foreign ID has
    /// the same 404 response, so the route does not disclose credential records.
    func revokeAPIKey(req: Request) async throws -> Response {
        guard let keyID = req.parameters.get("apiKeyID", as: UUID.self) else {
            throw Abort(.notFound)
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
        return req.redirect(to: "/app/settings/api-keys")
    }
}
