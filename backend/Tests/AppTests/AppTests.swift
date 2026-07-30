@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Flowboard web application")
struct AppTests {
    @Test("Health endpoint reports the service state")
    func healthCheck() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "health")
            #expect(response.status == .ok)
            expectContains(response.body.string, "\"status\":\"ok\"")
        }
    }

    @Test("Board data requires an authenticated session")
    func boardDataRequiresAuthentication() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "api/v1/boards")
            #expect(response.status == .unauthorized)
        }
    }

    @Test("Registration creates a persistent session and first board")
    func registrationCreatesWorkspace() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let boards = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: ["Cookie": session.cookie]
            )

            #expect(boards.status == .ok)
            expectContains(boards.body.string, "\"name\":\"My board\"")
            expectContains(boards.body.string, session.boardID.uuidString)
            let viewCount = try await BoardView.query(on: app.db)
                .filter(\.$board.$id == session.boardID)
                .count()
            #expect(viewCount == 4)
        }
    }

    @Test("An authenticated user can create and list tasks")
    func taskLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let input = CreateTaskRequest(
                boardID: session.boardID,
                title: "Test the release notes",
                description: nil,
                status: .backlog,
                priority: .high,
                labels: ["QA"],
                dueAt: nil
            )

            let created = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(input)
                }
            )
            #expect(created.status == .created)
            expectContains(created.body.string, "Test the release notes")

            let listed = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks?page=1&per=25",
                headers: ["Cookie": session.cookie]
            )
            #expect(listed.status == .ok)
            expectContains(listed.body.string, "\"boardName\":\"My board\"")
        }
    }

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

            #expect(callback.status == .unprocessableEntity)
            expectContains(callback.body.string, "could not be verified")
            #expect(try await OAuthAccount.query(on: app.db).count() == 0)
        }
    }

    /// Registers through the public API and returns the cookie plus the board that
    /// the registration transaction creates. Tests then exercise the real guard.
    private func register(on app: Application) async throws -> (cookie: String, boardID: UUID) {
        let input = RegisterRequest(
            name: "Test User",
            email: "\(UUID().uuidString.lowercased())@example.com",
            password: "correct-horse-battery"
        )
        let response = try await app.testing().sendRequest(
            .POST,
            "api/v1/auth/register",
            beforeRequest: { request in
                try request.content.encode(input)
            }
        )
        #expect(response.status == .created)

        let setCookie = try #require(response.headers[.setCookie].first)
        let cookie = String(try #require(setCookie.split(separator: ";").first))
        let user = try response.content.decode(UserResponse.self)
        let board = try #require(
            try await Board.query(on: app.db)
                .filter(\.$owner.$id == user.id)
                .first()
        )
        return (cookie, try board.requireID())
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
            redirectURL: "http://localhost:8080/oauth/callback"
        )
    }
}

/// Returns deterministic provider responses while validating the token request
/// and bearer profile request made by the application.
private final class OAuthTestClient: Client, Sendable {
    let eventLoop: any EventLoop

    init(eventLoop: any EventLoop) {
        self.eventLoop = eventLoop
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
                #"{"sub":"provider-user-123","email":"oauth@example.com","email_verified":true,"name":"OAuth User"}"#
            )
        default:
            response = .init(status: .notFound)
        }
        return eventLoop.makeSucceededFuture(response)
    }

    func delegating(to eventLoop: any EventLoop) -> any Client {
        OAuthTestClient(eventLoop: eventLoop)
    }

    private func jsonResponse(_ json: String) -> ClientResponse {
        ClientResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: ByteBufferAllocator().buffer(string: json)
        )
    }
}
