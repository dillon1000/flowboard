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

        let protected = routes.grouped(User.redirectMiddleware(path: "/login"))
        try protected.register(collection: AppPageController())
        try protected.register(collection: WorkspaceActionController())
    }

    func home(req: Request) -> Response {
        req.redirect(to: req.auth.has(User.self) ? "/app" : "/login")
    }

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", AuthPageContext(csrfToken: req.csrfToken))
    }

    func registerPage(req: Request) async throws -> View {
        try await req.view.render("register", AuthPageContext(csrfToken: req.csrfToken))
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
            AuthPageContext(csrfToken: req.csrfToken, error: message, email: email)
        )
        return try await page.encodeResponse(status: .unprocessableEntity, for: req)
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? any AbortError)?.reason ?? "Check the form and try again."
    }

}

private struct AuthPageContext: Encodable {
    let csrfToken: String
    let error: String?
    let email: String

    init(csrfToken: String, error: String? = nil, email: String = "") {
        self.csrfToken = csrfToken
        self.error = error
        self.email = email
    }
}
