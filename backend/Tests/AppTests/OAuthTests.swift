@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Flowboard OAuth")
struct OAuthTests {
    @Test("OAuth authorization creates a session, provider link, and workspace")
    func oauthAuthorizationCreatesWorkspace() async throws {
        try await withApp(configure: configure) { app in
            app.oauthConfiguration = try oauthConfiguration()
            app.clients.use { application in
                OAuthTestClient(eventLoop: application.eventLoopGroup.any())
            }

            let start = try await app.testing().sendRequest(.GET, "oauth/start")
            #expect(start.status == .seeOther)
            let location = try #require(start.headers.first(name: .location))
            let components = try #require(URLComponents(string: location))
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                }
            )
            let state = try #require(query["state"])
            #expect(query["response_type"] == "code")
            #expect(query["client_id"] == "test-client")
            #expect(query["scope"] == "openid profile email profile:picture")
            #expect(query["code_challenge_method"] == "S256")
            #expect((query["code_challenge"]?.count ?? 0) >= 43)

            let startCookieHeader = try #require(start.headers[.setCookie].first)
            #expect(startCookieHeader.contains("SameSite=Lax"))
            let startCookie = String(try #require(startCookieHeader.split(separator: ";").first))
            let callback = try await app.testing().sendRequest(
                .GET,
                "oauth/callback?code=test-code&state=\(state)",
                headers: ["Cookie": startCookie]
            )
            #expect(callback.status == .seeOther)
            #expect(callback.headers.first(name: .location) == "/app")

            let callbackCookie = callback.headers[.setCookie].first
                .flatMap { $0.split(separator: ";").first.map(String.init) }
                ?? startCookie
            let currentUser = try await app.testing().sendRequest(
                .GET,
                "api/v1/auth/me",
                headers: ["Cookie": callbackCookie]
            )
            #expect(currentUser.status == .ok)
            let user = try currentUser.content.decode(UserResponse.self)
            #expect(user.profilePictureURL == "https://images.example/avatar.png")

            let appPage = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace",
                headers: ["Cookie": callbackCookie]
            )
            #expect(appPage.status == .ok)
            expectContains(
                appPage.body.string,
                #""profilePictureURL":"https://images.example/avatar.png""#
            )

            let account = try #require(
                try await OAuthAccount.query(on: app.db)
                    .filter(\.$providerID == "test-provider")
                    .filter(\.$providerUserID == "provider-user-123")
                    .first()
            )
            #expect(account.$user.id == user.id)
            let boardCount = try await Board.query(on: app.db)
                .filter(\.$owner.$id == user.id)
                .count()
            #expect(boardCount == 1)

            app.clients.use { application in
                OAuthTestClient(
                    eventLoop: application.eventLoopGroup.any(),
                    pictureURL: "https://images.example/avatar-updated.png"
                )
            }
            let returningStart = try await app.testing().sendRequest(.GET, "oauth/start")
            let returningLocation = try #require(returningStart.headers.first(name: .location))
            let returningComponents = try #require(URLComponents(string: returningLocation))
            let returningState = try #require(
                returningComponents.queryItems?.first { $0.name == "state" }?.value
            )
            let returningCookieHeader = try #require(returningStart.headers[.setCookie].first)
            let returningCookie = String(
                try #require(returningCookieHeader.split(separator: ";").first)
            )
            let returningCallback = try await app.testing().sendRequest(
                .GET,
                "oauth/callback?code=test-code&state=\(returningState)",
                headers: ["Cookie": returningCookie]
            )
            #expect(returningCallback.status == .seeOther)
            let refreshedUser = try #require(try await User.find(user.id, on: app.db))
            #expect(refreshedUser.profilePictureURL == "https://images.example/avatar-updated.png")
            #expect(try await Board.query(on: app.db).count() == 1)
        }
    }

    @Test("OAuth callback rejects state from another browser session")
    func oauthCallbackRejectsInvalidState() async throws {
        try await withApp(configure: configure) { app in
            app.oauthConfiguration = try oauthConfiguration()
            app.clients.use { application in
                OAuthTestClient(eventLoop: application.eventLoopGroup.any())
            }

            let start = try await app.testing().sendRequest(.GET, "oauth/start")
            let setCookie = try #require(start.headers[.setCookie].first)
            let cookie = String(try #require(setCookie.split(separator: ";").first))
            let callback = try await app.testing().sendRequest(
                .GET,
                "oauth/callback?code=test-code&state=wrong-state",
                headers: ["Cookie": cookie]
            )

            #expect(callback.status == .seeOther)
            expectContains(
                callback.headers.first(name: .location),
                "/login?oauth_error=The%20OAuth%20login%20request%20could%20not%20be%20verified."
            )
            #expect(try await OAuthAccount.query(on: app.db).count() == 0)
        }
    }

    private func oauthConfiguration() throws -> OAuthConfiguration {
        try OAuthConfiguration(
            providerID: "test-provider",
            providerName: "Test OAuth",
            clientID: "test-client",
            clientSecret: "test-secret",
            authorizationURL: "https://provider.example/authorize",
            tokenURL: "https://provider.example/token",
            userInfoURL: "https://provider.example/userinfo",
            redirectURL: "http://localhost:8080/oauth/callback",
            scopes: ["openid", "profile", "email", "profile:picture"]
        )
    }
}

/// Returns deterministic provider responses while validating the token request
/// and bearer profile request made by the application.
private final class OAuthTestClient: Client, Sendable {
    let eventLoop: any EventLoop
    let pictureURL: String

    init(
        eventLoop: any EventLoop,
        pictureURL: String = "https://images.example/avatar.png"
    ) {
        self.eventLoop = eventLoop
        self.pictureURL = pictureURL
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        let response: ClientResponse
        switch request.url.path {
        case "/token":
            let body = request.body?.string ?? ""
            guard
                request.method == .POST,
                body.contains("code=test-code"),
                body.contains("code_verifier="),
                body.contains("client_id=test-client"),
                body.contains("client_secret=test-secret")
            else {
                return eventLoop.makeSucceededFuture(.init(status: .badRequest))
            }
            response = jsonResponse(
                #"{"access_token":"test-access-token","token_type":"Bearer"}"#
            )
        case "/userinfo":
            guard request.headers.bearerAuthorization?.token == "test-access-token" else {
                return eventLoop.makeSucceededFuture(.init(status: .unauthorized))
            }
            response = jsonResponse(
                #"{"sub":"provider-user-123","email":"oauth@example.com","email_verified":true,"name":"OAuth User","picture":"\#(pictureURL)"}"#
            )
        default:
            response = .init(status: .notFound)
        }
        return eventLoop.makeSucceededFuture(response)
    }

    func delegating(to eventLoop: any EventLoop) -> any Client {
        OAuthTestClient(eventLoop: eventLoop, pictureURL: pictureURL)
    }

    private func jsonResponse(_ json: String) -> ClientResponse {
        ClientResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: ByteBufferAllocator().buffer(string: json)
        )
    }
}
