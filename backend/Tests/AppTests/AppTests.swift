@testable import App
import Testing
import VaporTesting

@Suite("Flowboard API")
struct AppTests {
    @Test("Health endpoint reports the service state")
    func healthCheck() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health") { response in
                #expect(response.status == .ok)
                expectContains(response.body.string, "\"status\":\"ok\"")
            }
        }
    }

    @Test("Default board includes seeded work")
    func defaultBoardIncludesSeededTasks() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "api/v1/boards/default") { response in
                #expect(response.status == .ok)
                expectContains(response.body.string, "\"slug\":\"launch-week\"")
                expectContains(response.body.string, "\"tasks\"")
            }
        }
    }

    @Test("Task creation persists through the API")
    func taskLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let request = CreateTaskRequest(
                boardID: SeedWorkspace.boardID,
                title: "Test the release notes",
                description: nil,
                status: .backlog,
                priority: .high,
                labels: ["QA"],
                dueAt: nil
            )

            try await app.testing().test(
                .POST,
                "api/v1/tasks",
                beforeRequest: { requestMessage in
                    try requestMessage.content.encode(request)
                },
                afterResponse: { response in
                    #expect(response.status == .created)
                    expectContains(response.body.string, "Test the release notes")
                }
            )
        }
    }
}
