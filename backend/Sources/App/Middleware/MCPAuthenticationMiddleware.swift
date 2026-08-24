import Vapor

struct MCPAuthenticationMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let bearer = req.headers.bearerAuthorization,
              let user = try await MCPOAuthService.authenticate(bearer.token, on: req.db) else {
            let response = Response(status: .unauthorized)
            if let origin = try? MCPOAuthService.publicOrigin(for: req) {
                response.headers.replaceOrAdd(
                    name: .wwwAuthenticate,
                    value: "Bearer resource_metadata=\"\(origin)/.well-known/oauth-protected-resource/mcp\""
                )
            }
            return response
        }
        req.auth.login(user)
        return try await next.respond(to: req)
    }
}
