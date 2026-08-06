import Vapor

/// Accepts only the restricted Canvas Bearer credential. Browser sessions and
/// general API keys cannot enter extension routes.
struct CanvasCredentialMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard
            let bearer = req.headers.bearerAuthorization,
            let connection = try await CanvasCredentialService.authenticate(bearer.token, on: req.db)
        else {
            throw Abort(.unauthorized, reason: "Invalid Canvas sync key.")
        }
        req.auth.login(connection)
        return try await next.respond(to: req)
    }
}
