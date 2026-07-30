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
        protected.get("app", use: appShell)
        protected.get("app", "**", use: appShell)
    }

    func home(req: Request) -> Response {
        req.redirect(to: req.auth.has(User.self) ? "/app" : "/login")
    }

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", AuthPageContext())
    }

    func registerPage(req: Request) async throws -> View {
        try await req.view.render("register", AuthPageContext())
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

    func appShell(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        return try await req.view.render(
            "app",
            AppPageContext(
                userName: user.name,
                userEmail: user.email,
                userInitials: initials(for: user.name)
            )
        )
    }

    private func renderAuthError(
        _ view: String,
        message: String,
        email: String,
        for req: Request
    ) async throws -> Response {
        let page = try await req.view.render(view, AuthPageContext(error: message, email: email))
        return try await page.encodeResponse(status: .unprocessableEntity, for: req)
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? any AbortError)?.reason ?? "Check the form and try again."
    }

    private func initials(for name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}

private struct AuthPageContext: Encodable {
    let error: String?
    let email: String

    init(error: String? = nil, email: String = "") {
        self.error = error
        self.email = email
    }
}

private struct AppPageContext: Encodable {
    let userName: String
    let userEmail: String
    let userInitials: String
}
