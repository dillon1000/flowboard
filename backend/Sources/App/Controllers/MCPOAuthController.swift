import Fluent
import Foundation
import Vapor

struct MCPOAuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(".well-known", "oauth-authorization-server", use: authorizationServerMetadata)
        routes.get(".well-known", "oauth-protected-resource", use: protectedResourceMetadata)
        routes.get(".well-known", "oauth-protected-resource", "mcp", use: protectedResourceMetadata)

        let oauth = routes.grouped("oauth")
        oauth.post("register", use: register)
        oauth.post("token", use: token)

        let browserOAuth = oauth.grouped(User.sessionAuthenticator())
        browserOAuth.get("authorize", use: authorize)
        browserOAuth.post("authorize", use: authorizeDecision)
    }

    func authorizationServerMetadata(req: Request) throws -> Response {
        let origin = try MCPOAuthService.publicOrigin(for: req)
        return try jsonResponse(MCPJSONValue.object([
            "issuer": .string(origin),
            "authorization_endpoint": .string("\(origin)/oauth/authorize"),
            "token_endpoint": .string("\(origin)/oauth/token"),
            "registration_endpoint": .string("\(origin)/oauth/register"),
            "response_types_supported": .array([.string("code")]),
            "grant_types_supported": .array([.string("authorization_code"), .string("refresh_token")]),
            "code_challenge_methods_supported": .array([.string("S256")]),
            "token_endpoint_auth_methods_supported": .array([.string("none")]),
            "scopes_supported": .array([.string(MCPOAuthService.scope)]),
        ]))
    }

    func protectedResourceMetadata(req: Request) throws -> Response {
        let origin = try MCPOAuthService.publicOrigin(for: req)
        return try jsonResponse(MCPJSONValue.object([
            "resource": .string("\(origin)/mcp"),
            "authorization_servers": .array([.string(origin)]),
            "bearer_methods_supported": .array([.string("header")]),
            "scopes_supported": .array([.string(MCPOAuthService.scope)]),
            "resource_documentation": .string("\(origin)/api/v1"),
        ]))
    }

    func register(req: Request) async throws -> Response {
        do {
            let input = try req.content.decode(MCPOAuthClientRegistrationRequest.self)
            let client = try await MCPOAuthService.createClient(input: input, on: req.db)
            return try await MCPOAuthClientRegistrationResponse(
                clientID: client.clientID,
                clientName: client.clientName,
                redirectURIs: client.redirectURIs
            ).encodeResponse(status: .created, for: req)
        } catch let error as AbortError {
            return try await oauthError(
                "invalid_client_metadata",
                description: error.reason,
                status: .badRequest,
                for: req
            )
        }
    }

    func authorize(req: Request) async throws -> Response {
        let input: MCPOAuthAuthorizationQuery
        do {
            input = try req.query.decode(MCPOAuthAuthorizationQuery.self)
        } catch {
            throw Abort(.badRequest, reason: "The OAuth authorization request is incomplete.")
        }
        let client = try await MCPOAuthService.validatedAuthorization(
            input,
            resourceURL: MCPOAuthService.resourceURL(for: req),
            on: req.db
        )
        guard req.auth.has(User.self) else {
            var login = URLComponents()
            login.path = "/login"
            login.queryItems = [URLQueryItem(name: "returnTo", value: req.url.string)]
            return req.redirect(to: login.string ?? "/login")
        }
        return consentPage(
            client: client,
            input: input,
            user: try req.auth.require(User.self)
        )
    }

    func authorizeDecision(req: Request) async throws -> Response {
        guard let user = req.auth.get(User.self) else {
            throw Abort(.unauthorized, reason: "Sign in before authorizing this client.")
        }
        let input = try req.content.decode(MCPOAuthAuthorizationDecision.self)
        let query = MCPOAuthAuthorizationQuery(
            responseType: input.responseType,
            clientID: input.clientID,
            redirectURI: input.redirectURI,
            codeChallenge: input.codeChallenge,
            codeChallengeMethod: input.codeChallengeMethod,
            state: input.state,
            scope: input.scope,
            resource: input.resource
        )
        let client = try await MCPOAuthService.validatedAuthorization(
            query,
            resourceURL: MCPOAuthService.resourceURL(for: req),
            on: req.db
        )
        if input.decision != "allow" {
            return redirect(
                to: input.redirectURI,
                items: [
                    URLQueryItem(name: "error", value: "access_denied"),
                    URLQueryItem(name: "state", value: input.state),
                ]
            )
        }
        let code = try await MCPOAuthService.issueAuthorizationCode(
            input: input,
            userID: user.requireID(),
            client: client,
            on: req.db
        )
        return redirect(
            to: input.redirectURI,
            items: [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: input.state),
            ]
        )
    }

    func token(req: Request) async throws -> Response {
        do {
            let input = try req.content.decode(MCPOAuthTokenRequest.self)
            let response = try await MCPOAuthService.exchange(
                input: input,
                resourceURL: MCPOAuthService.resourceURL(for: req),
                on: req.db
            )
            let encoded = try jsonResponse(MCPJSONValue.object([
                "access_token": .string(response.accessToken),
                "token_type": .string(response.tokenType),
                "expires_in": .integer(response.expiresIn),
                "refresh_token": .string(response.refreshToken),
                "scope": .string(response.scope),
            ]))
            encoded.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            encoded.headers.replaceOrAdd(name: .pragma, value: "no-cache")
            return encoded
        } catch OAuthExchangeError.unsupportedGrantType {
            return try await oauthError(
                "unsupported_grant_type",
                description: "Use authorization_code or refresh_token.",
                status: .badRequest,
                for: req
            )
        } catch {
            return try await oauthError(
                "invalid_grant",
                description: "The authorization grant is invalid or expired.",
                status: .badRequest,
                for: req
            )
        }
    }

    private func consentPage(
        client: MCPOAuthClient,
        input: MCPOAuthAuthorizationQuery,
        user: User
    ) -> Response {
        let fields: [(String, String?)] = [
            ("response_type", input.responseType),
            ("client_id", input.clientID),
            ("redirect_uri", input.redirectURI),
            ("code_challenge", input.codeChallenge),
            ("code_challenge_method", input.codeChallengeMethod),
            ("state", input.state),
            ("scope", input.scope ?? MCPOAuthService.scope),
            ("resource", input.resource),
        ]
        let hiddenFields = fields.compactMap { name, value in
            value.map { "<input type=\"hidden\" name=\"\(html(name))\" value=\"\(html($0))\">" }
        }.joined()
        let body = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>Connect \(html(client.clientName)) · Focalboard</title>
          <style>
            :root{color-scheme:light;--canvas:#fff;--surface:#fff;--sunken:#fafafa;--hover:#f2f2f2;--text:#171717;--secondary:#666;--tertiary:#8f8f8f;--border:rgb(0 0 0/8%);--border-strong:rgb(0 0 0/16%);--primary:#171717;--on-primary:#fff;--danger:#c93636;font-family:'Rubik Variable',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-synthesis:none}
            @media(prefers-color-scheme:dark){:root{color-scheme:dark;--canvas:#0a0a0a;--surface:#111;--sunken:#181818;--hover:#222;--text:#ededed;--secondary:#a1a1a1;--tertiary:#737373;--border:rgb(255 255 255/10%);--border-strong:rgb(255 255 255/18%);--primary:#ededed;--on-primary:#171717;--danger:#ff6969}.wordmark{filter:invert(1)}}
            *{box-sizing:border-box}body{min-height:100vh;margin:0;color:var(--text);background:var(--canvas);-webkit-font-smoothing:antialiased}.topbar{display:flex;height:64px;align-items:center;justify-content:space-between;padding:0 28px;border-bottom:1px solid var(--border)}.wordmark{display:block;width:112px;height:auto}.account{color:var(--secondary);font-size:12px}.shell{display:grid;min-height:calc(100vh - 64px);place-items:center;padding:56px 24px}.consent{width:min(100%,520px)}.eyebrow{display:flex;align-items:center;gap:8px;margin:0 0 14px;color:var(--secondary);font-size:12px;font-weight:500}.eyebrow span{display:grid;width:28px;height:28px;place-items:center;border-radius:8px;background:var(--sunken);box-shadow:inset 0 0 0 1px var(--border)}h1{margin:0;font-size:28px;line-height:1.2;letter-spacing:-.025em}h1 strong{font-weight:650}.lede{max-width:460px;margin:10px 0 28px;color:var(--secondary);font-size:14px;line-height:1.6}.permission{overflow:hidden;border-radius:12px;background:var(--surface);box-shadow:0 0 0 1px var(--border),0 8px 24px -16px rgb(0 0 0/25%)}.permission-head{display:flex;gap:12px;padding:17px 18px}.permission-icon{display:grid;flex:0 0 auto;width:34px;height:34px;place-items:center;border-radius:9px;color:var(--text);background:var(--sunken);box-shadow:inset 0 0 0 1px var(--border)}.permission-copy{display:grid;gap:3px}.permission-copy strong{font-size:13px;font-weight:600}.permission-copy span{color:var(--secondary);font-size:12px;line-height:1.5}.details{display:grid;gap:9px;margin:0;padding:14px 18px 16px;border-top:1px solid var(--border);background:var(--sunken);color:var(--secondary);font-size:12px;line-height:1.45}.details div{display:flex;gap:9px}.check{color:var(--text);font-weight:700}.security{margin:16px 2px 0;color:var(--tertiary);font-size:11px;line-height:1.55}.actions{display:flex;justify-content:flex-end;gap:8px;margin-top:24px}button{min-height:38px;padding:0 15px;border:0;border-radius:8px;font:500 13px inherit;cursor:pointer;transition:background .15s ease,transform .15s ease}.deny{color:var(--text);background:var(--surface);box-shadow:0 0 0 1px var(--border-strong)}.deny:hover{background:var(--hover)}.allow{color:var(--on-primary);background:var(--primary)}.allow:hover{opacity:.88}button:active{transform:translateY(1px)}button:focus-visible{outline:2px solid #0070f3;outline-offset:2px}.footer{margin-top:26px;text-align:center;color:var(--tertiary);font-size:11px}.footer a{color:inherit;text-decoration:underline;text-underline-offset:3px}@media(max-width:560px){.topbar{height:56px;padding:0 18px}.account{max-width:48vw;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.shell{min-height:calc(100vh - 56px);padding:34px 18px;place-items:start center}h1{font-size:24px}.actions{display:grid;grid-template-columns:1fr 1fr}.actions button{width:100%}}
          </style>
        </head>
        <body>
          <header class="topbar"><a href="/app" aria-label="Focalboard home"><img class="wordmark" src="/focalboard-wordmark.webp" alt="Focalboard" width="112" height="15"></a><span class="account">\(html(user.email))</span></header>
          <main class="shell"><section class="consent" aria-labelledby="consent-title">
            <p class="eyebrow"><span aria-hidden="true">✦</span>Connected app request</p>
            <h1 id="consent-title">Connect <strong>\(html(client.clientName))</strong>?</h1>
            <p class="lede">This client wants to use Focalboard as a read-only source for your boards, assignments, and course planning.</p>
            <div class="permission">
              <div class="permission-head"><span class="permission-icon" aria-hidden="true">⌁</span><span class="permission-copy"><strong>Read workspace data</strong><span>Access is limited to information you can already view in Focalboard.</span></span></div>
              <div class="details"><div><span class="check">✓</span><span>Boards, task descriptions, dates, custom fields, and grades</span></div><div><span class="check">✓</span><span>Linked Canvas courses, assignments, and submission status</span></div></div>
            </div>
            <p class="security">This app cannot edit your workspace or access passwords, API keys, Canvas sync credentials, or attachment contents. You can disconnect it any time in Settings → Connected apps.</p>
            <form method="post" action="/oauth/authorize">\(hiddenFields)<div class="actions"><button class="deny" name="decision" value="deny">Cancel</button><button class="allow" name="decision" value="allow">Allow access</button></div></form>
            <p class="footer">Signed in as \(html(user.name)) · <a href="/app/settings/connected-apps">Manage connected apps</a></p>
          </section></main>
        </body>
        </html>
        """
        let response = Response(status: .ok, body: .init(string: body))
        response.headers.contentType = .html
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        response.headers.replaceOrAdd(name: "x-frame-options", value: "DENY")
        return response
    }

    private func redirect(to value: String, items: [URLQueryItem]) -> Response {
        guard var components = URLComponents(string: value) else {
            return Response(status: .badRequest)
        }
        components.queryItems = (components.queryItems ?? []) + items.filter { $0.value != nil }
        let response = Response(status: .seeOther)
        response.headers.replaceOrAdd(name: .location, value: components.string ?? value)
        return response
    }

    private func oauthError(
        _ error: String,
        description: String,
        status: HTTPResponseStatus,
        for req: Request
    ) async throws -> Response {
        try await MCPOAuthErrorResponse(error: error, errorDescription: description)
            .encodeResponse(status: status, for: req)
    }

    private func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
