@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Board workflow customization")
struct WorkflowCustomizationTests {
    @Test("An administrator can add and use custom status and severity values")
    func addAndUseCustomTaskOptions() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let settings = try await app.testing().sendRequest(
                .GET,
                "app/boards/\(session.boardID)/settings",
                headers: ["Cookie": session.cookie]
            )
            let csrfToken = try csrfToken(from: settings.body.string)

            let statusResponse = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/task-options",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        [
                            "kind": "status",
                            "name": "Released",
                            "color": "green",
                            "isCompleted": "true",
                        ],
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(statusResponse.status == .seeOther)

            let severityResponse = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/task-options",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        [
                            "kind": "severity",
                            "name": "Critical",
                            "color": "red",
                        ],
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(severityResponse.status == .seeOther)

            let taskResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskRequest(
                            boardID: session.boardID,
                            title: "Verify the release",
                            description: nil,
                            status: TaskStatus(rawValue: "released"),
                            priority: TaskPriority(rawValue: "critical"),
                            labels: [],
                            dueAt: nil
                        )
                    )
                }
            )
            #expect(taskResponse.status == .created)
            let task = try taskResponse.content.decode(TaskResponse.self)
            #expect(task.status.rawValue == "released")
            #expect(task.priority.rawValue == "critical")

            let board = try #require(try await Board.find(session.boardID, on: app.db))
            #expect(board.statusOption(for: task.status).name == "Released")
            #expect(board.isCompleted(task.status))
            #expect(board.severityOption(for: task.priority).name == "Critical")

            let summaries = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: ["Cookie": session.cookie]
            )
            let summary = try #require(
                try summaries.content.decode([BoardSummaryResponse].self).first {
                    $0.id == session.boardID
                }
            )
            #expect(summary.completedCount == 1)

            let view = try #require(
                try await BoardView.query(on: app.db)
                    .filter(\.$board.$id == session.boardID)
                    .sort(\.$position, .ascending)
                    .first()
            )
            let boardPage = try await app.testing().sendRequest(
                .GET,
                "app/boards/\(session.boardID)/views/\(try view.requireID())",
                headers: ["Cookie": session.cookie]
            )
            #expect(boardPage.status == .ok)
            expectContains(boardPage.body.string, "Released")
            expectContains(boardPage.body.string, "Critical")
        }
    }

    private func csrfToken(from page: String) throws -> String {
        let marker = #"name="csrf-token" content=""#
        let start = try #require(page.range(of: marker)?.upperBound)
        let end = try #require(page[start...].firstIndex(of: "\""))
        return String(page[start..<end])
    }
}
