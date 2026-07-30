@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    func testHealthCheck() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        try app.test(.GET, "health") { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContains(response.body.string, "\"status\":\"ok\"")
        }
    }

    func testDefaultBoardIncludesSeededTasks() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        try app.test(.GET, "api/v1/boards/default") { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContains(response.body.string, "\"slug\":\"launch-week\"")
            XCTAssertContains(response.body.string, "\"tasks\"")
        }
    }

    func testTaskLifecycle() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        let request = CreateTaskRequest(
            boardID: SeedWorkspace.boardID,
            title: "Test the release notes",
            description: nil,
            status: .backlog,
            priority: .high,
            labels: ["QA"],
            dueAt: nil
        )

        try app.test(.POST, "api/v1/tasks", beforeRequest: { requestMessage in
            try requestMessage.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .created)
            XCTAssertContains(response.body.string, "Test the release notes")
        })
    }
}
