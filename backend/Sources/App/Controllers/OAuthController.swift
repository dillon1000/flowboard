import Leaf
import Vapor

struct OAuthController: RouteCollection {
    private let stateSessionKey = "oauth-state"
    private let verifierSessionKey = "oauth-code-verifier"

    func boot(routes: any RoutesBuilder) throws {
        routes.get("oauth", "start", use: start)
        routes.get("oauth", "callback", use: callback)
    }

    /// Starts one authorization-code transaction and stores only its short-lived
    /// state and verifier in the server-side session.
    func start(req: Request) throws -> Response {
        guard let configuration = req.application.oauthConfiguration else {
            throw Abort(.notFound)
        }
        if req.auth.has(User.self) {
            return req.redirect(to: "/app")
        }

        let state = OAuthService.randomURLSafeValue()
        let verifier = OAuthService.randomURLSafeValue()
        req.session.data[stateSessionKey] = state
        req.session.data[verifierSessionKey] = verifier

        let url = try OAuthService.authorizationURL(
            configuration: configuration,
            state: state,
            codeChallenge: OAuthService.codeChallenge(for: verifier)
        )
        return req.redirect(to: url)
    }

    /// Completes the transaction once. Session values are removed before network
    /// calls, so a callback cannot replay a code after a provider or database error.
    func callback(req: Request) async throws -> Response {
        do {
            guard let configuration = req.application.oauthConfiguration else {
                throw Abort(.notFound)
            }
            let query = try req.query.decode(OAuthCallbackQuery.self)
            if query.error != nil {
                throw Abort(.unauthorized, reason: "OAuth authorization was canceled.")
            }
            guard
                let code = query.code,
                !code.isEmpty,
                let returnedState = query.state,
                let expectedState = req.session.data[stateSessionKey],
                let verifier = req.session.data[verifierSessionKey]
            else {
                throw Abort(.badRequest, reason: "The OAuth login request expired. Start again.")
            }

            clearTransaction(from: req)
            guard returnedState == expectedState else {
                throw Abort(.badRequest, reason: "The OAuth login request could not be verified.")
            }

            let profile = try await OAuthService.profile(
                code: code,
                codeVerifier: verifier,
                configuration: configuration,
                client: req.client
            )
            let user = try await AuthService.authenticateOAuth(
                profile,
                providerID: configuration.providerID,
                requiresVerifiedEmail: configuration.requiresVerifiedEmail,
                on: req.db
            )
            req.auth.login(user)
            return req.redirect(to: "/app")
        } catch {
            clearTransaction(from: req)
            let message = (error as? any AbortError)?.reason
                ?? "OAuth login failed. Try again."
            let page = try await req.view.render(
                "login",
                AuthPageContext(request: req, error: message)
            )
            return try await page.encodeResponse(status: .unprocessableEntity, for: req)
        }
    }

    private func clearTransaction(from req: Request) {
        req.session.data[stateSessionKey] = nil
        req.session.data[verifierSessionKey] = nil
    }
}

private struct OAuthCallbackQuery: Content {
    let code: String?
    let state: String?
    let error: String?
}
