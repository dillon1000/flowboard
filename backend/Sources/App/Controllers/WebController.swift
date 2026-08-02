import Leaf
import Vapor

struct WebController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: home)
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.get("register", use: registerPage)
        routes.post("register", use: register)
        routes.post("logout", use: logout)
        routes.get("t", use: tapPage)

        let protected = routes.grouped(User.redirectMiddleware(path: "/login"))
        try protected.register(collection: AppPageController())
        try protected.register(collection: WorkspaceActionController())

        // The catch-all has the lowest route priority, so known pages and assets
        // resolve first. Unknown API paths keep Vapor's JSON error contract.
        routes.get(.catchall, use: notFoundPage)
    }

    func home(req: Request) -> Response {
        req.redirect(to: req.auth.has(User.self) ? "/app" : "/login")
    }

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", AuthPageContext(request: req))
    }

    func registerPage(req: Request) async throws -> View {
        try await req.view.render("register", AuthPageContext(request: req))
    }

    /// Serves the cacheable, session-free Tap runner. The capability stays in
    /// the URL fragment, so this request and Railway access logs never receive it.
    func tapPage(req: Request) async throws -> Response {
        let page = try await req.view.render("tap")
        let response = try await page.encodeResponse(for: req)
        response.headers.replaceOrAdd(
            name: .cacheControl,
            value: "public, max-age=3600, stale-while-revalidate=86400"
        )
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
        response.headers.replaceOrAdd(name: "X-Robots-Tag", value: "noindex, nofollow")
        response.headers.replaceOrAdd(
            name: "Content-Security-Policy",
            value: "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        )
        return response
    }

    func notFoundPage(req: Request) async throws -> Response {
        guard !req.url.path.hasPrefix("/api/") else {
            throw Abort(.notFound)
        }
        let page = try await req.view.render("not-found", NotFoundPageContext(request: req))
        return try await page.encodeResponse(status: .notFound, for: req)
    }

    func login(req: Request) async throws -> Response {
        do {
            try LoginRequest.validate(content: req)
            let input = try req.content.decode(LoginRequest.self)
            let user = try await AuthService.authenticate(input, on: req.db)
            req.auth.login(user)
            return req.redirect(to: "/app")
        } catch {
            return try await renderAuthError(
                "login",
                message: errorMessage(error),
                email: (try? req.content.get(String.self, at: "email")) ?? "",
                for: req
            )
        }
    }

    func register(req: Request) async throws -> Response {
        do {
            try RegisterRequest.validate(content: req)
            let input = try req.content.decode(RegisterRequest.self)
            let user = try await AuthService.register(input, on: req.db)
            req.auth.login(user)
            return req.redirect(to: "/app")
        } catch {
            return try await renderAuthError(
                "register",
                message: errorMessage(error),
                email: (try? req.content.get(String.self, at: "email")) ?? "",
                for: req
            )
        }
    }

    func logout(req: Request) -> Response {
        req.auth.logout(User.self)
        req.session.destroy()
        return req.redirect(to: "/login")
    }

    private func renderAuthError(
        _ view: String,
        message: String,
        email: String,
        for req: Request
    ) async throws -> Response {
        let page = try await req.view.render(
            view,
            AuthPageContext(request: req, error: message, email: email)
        )
        return try await page.encodeResponse(status: .unprocessableEntity, for: req)
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? any AbortError)?.reason ?? "Check the form and try again."
    }
}

struct AuthPageContext: Encodable {
    let csrfToken: String
    let error: String?
    let email: String
    let oauthEnabled: Bool
    let oauthProviderName: String

    init(request: Request, error: String? = nil, email: String = "") {
        self.csrfToken = request.csrfToken
        self.error = error
        self.email = email
        self.oauthEnabled = request.application.oauthConfiguration != nil
        self.oauthProviderName = request.application.oauthConfiguration?.providerName ?? "OAuth"
    }
}

struct NotFoundPageContext: Encodable {
    let destination: String
    let actionLabel: String

    init(request: Request) {
        let isAuthenticated = request.auth.has(User.self)
        self.destination = isAuthenticated ? "/app" : "/login"
        self.actionLabel = isAuthenticated ? "Return to workspace" : "Go to sign in"
    }
}
