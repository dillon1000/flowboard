@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Flowboard application API")
struct AppTests {
    @Test("Health endpoint reports the service state")
    func healthCheck() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "health")
            #expect(response.status == .ok)
            expectContains(response.body.string, "\"status\":\"ok\"")
            #expect(response.headers.first(name: .flowboardServerName) == "flowboard-server")
            #expect(response.headers.first(name: .flowboardServerVersion) == "0.1.0")
            let serverTime = try #require(response.headers.first(name: .flowboardServerTime))
            #expect(ISO8601DateFormatter().date(from: serverTime) != nil)
        }
    }

    @Test("Unknown API routes keep the JSON error contract")
    func unknownAPIRouteReturnsJSON() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "api/v1/missing")

            #expect(response.status == .notFound)
            #expect(response.headers.contentType == .json)
            expectContains(response.body.string, "\"error\":true")
        }
    }

    @Test("Private board data requires authentication")
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

    @Test("Task mutations appear in workspace page data")
    func taskLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let created = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskRequest(
                            boardID: session.boardID,
                            title: "Test the release notes",
                            description: "Review the Svelte output.",
                            status: .backlog,
                            priority: .high,
                            labels: ["QA"],
                            dueAt: nil
                        )
                    )
                }
            )
            #expect(created.status == .created)
            let createdTask = try created.content.decode(TaskResponse.self)
            let storedTask = try #require(try await Task.find(createdTask.id, on: app.db))
            #expect(storedTask.$creator.id == session.userID)

            let pageData = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/tasks/\(storedTask.publicID)",
                headers: ["Cookie": session.cookie]
            )
            #expect(pageData.status == .ok)
            expectContains(pageData.body.string, "Test the release notes")
            expectContains(pageData.body.string, "\"boardName\":\"My board\"")
            expectContains(pageData.body.string, "\"creatorName\":\"Test User\"")

            let promoted = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/tasks/\(createdTask.id)",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(["status": "done"])
                }
            )
            #expect(promoted.status == .ok)
            #expect(try promoted.content.decode(TaskResponse.self).status == .done)

            let listed = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks?page=1&per=25",
                headers: ["Cookie": session.cookie]
            )
            #expect(listed.status == .ok)
            expectContains(listed.body.string, "\"boardName\":\"My board\"")
        }
    }

    @Test("Archived tasks leave active page data and can be restored")
    func archivedTaskRecovery() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let task = Task(
                boardID: session.boardID,
                title: "Recover the archived task",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()

            let archived = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/tasks/\(taskID)",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(["isArchived": true])
                }
            )
            #expect(archived.status == .ok)

            let activeTasks = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/tasks",
                headers: ["Cookie": session.cookie]
            )
            #expect(!activeTasks.body.string.contains("Recover the archived task"))
            let archivedTasks = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/tasks/archived",
                headers: ["Cookie": session.cookie]
            )
            #expect(archivedTasks.status == .ok)
            expectContains(archivedTasks.body.string, "Recover the archived task")

            let restored = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/tasks/\(taskID)",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(["isArchived": false])
                }
            )
            #expect(restored.status == .ok)
            #expect(!(try #require(try await Task.find(taskID, on: app.db))).isArchived)
        }
    }
}
