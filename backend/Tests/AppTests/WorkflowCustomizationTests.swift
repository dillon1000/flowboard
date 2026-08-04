@testable import App
import Fluent
import Testing
import Vapor
import VaporTesting

@Suite("Board workflow customization")
struct WorkflowCustomizationTests {
    @Test("An administrator can add and use custom workflow values")
    func addAndUseCustomTaskOptions() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let green = try #require(BoardTaskOptionColor(rawValue: "green"))
            let purple = try #require(BoardTaskOptionColor(rawValue: "#b144dd"))
            let statusResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(session.boardID)/task-options",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskOptionTestRequest(
                            kind: "status",
                            name: "Released",
                            color: green,
                            isCompleted: true
                        )
                    )
                }
            )
            #expect(statusResponse.status == .ok)

            let severityResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(session.boardID)/task-options",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskOptionTestRequest(
                            kind: "severity",
                            name: "Critical",
                            color: purple,
                            isCompleted: false
                        )
                    )
                }
            )
            #expect(severityResponse.status == .ok)

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
            #expect(board.severityOption(for: task.priority).color.rawValue == "#b144dd")

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
            let boardData = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/boards/\(session.boardID)/views/\(try view.requireID())",
                headers: ["Cookie": session.cookie]
            )
            #expect(boardData.status == .ok)
            expectContains(boardData.body.string, "Released")
            expectContains(boardData.body.string, "Critical")
            expectContains(boardData.body.string, "#b144dd")
        }
    }
}

private struct CreateTaskOptionTestRequest: Content {
    let kind: String
    let name: String
    let color: BoardTaskOptionColor
    let isCompleted: Bool
}
