import Vapor

struct CSRFMiddleware: AsyncMiddleware {
    /// Protects browser form routes while leaving the versioned JSON API available
    /// to non-browser clients. Turbo sends the meta token as an HTTP header, and a
    /// hidden form field supports requests made before JavaScript starts.
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if req.session.data["csrf-token"] == nil {
            req.session.data["csrf-token"] = UUID().uuidString
        }

        let mutatingMethods: [HTTPMethod] = [.POST, .PUT, .PATCH, .DELETE]
        if mutatingMethods.contains(req.method), !req.url.path.hasPrefix("/api/") {
            let submitted = req.headers.first(name: "X-CSRF-TOKEN")
                ?? (try? req.content.get(String.self, at: "_csrf"))
            guard
                let expected = req.session.data["csrf-token"],
                let submitted,
                submitted == expected
            else {
                throw Abort(.forbidden, reason: "This form expired. Refresh the page and try again.")
            }
        }

        return try await next.respond(to: req)
    }
}

extension Request {
    var csrfToken: String {
        if let token = session.data["csrf-token"] {
            return token
        }
        let token = UUID().uuidString
        session.data["csrf-token"] = token
        return token
    }
}
