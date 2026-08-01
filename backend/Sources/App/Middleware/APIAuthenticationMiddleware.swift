import Fluent
import Vapor

/// Authenticates REST resources with one Bearer API key or an existing session.
/// An Authorization header is authoritative: invalid headers cannot fall back to
/// a browser session, and valid keys are never written into session state.
struct APIAuthenticationMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if req.headers.first(name: .authorization) != nil {
            guard
                let bearer = req.headers.bearerAuthorization,
                let credential = try await APIKeyService.authenticate(bearer.token, on: req.db)
            else {
                throw Abort(.unauthorized, reason: "Invalid API key.")
            }

            req.auth.login(credential.user)
            await recordUse(of: credential, for: req)
            return try await next.respond(to: req)
        }

        if let userID = req.session.authenticated(User.self) {
            if let user = try await User.find(userID, on: req.db) {
                req.auth.login(user)
            } else {
                req.session.unauthenticate(User.self)
            }
        }
        return try await next.respond(to: req)
    }

    /// Updates usage at most once every five minutes to limit database writes.
    /// A metadata write failure is logged but does not reject a valid API request.
    private func recordUse(of credential: APIKeyCredential, for req: Request) async {
        let now = Date()
        if let lastUsedAt = credential.lastUsedAt,
           lastUsedAt > now.addingTimeInterval(-300) {
            return
        }

        credential.lastUsedAt = now
        do {
            try await credential.update(on: req.db)
        } catch {
            req.logger.warning("Could not update API key usage: \(error)")
        }
    }
}
