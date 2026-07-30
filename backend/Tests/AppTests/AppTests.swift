@testable import App
import Fluent
import Testing
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
}
