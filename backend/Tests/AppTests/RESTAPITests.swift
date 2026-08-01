@testable import App
import Fluent
import NIOCore
import Testing
import Vapor
import VaporTesting

@Suite("REST API")
struct RESTAPITests {
    @Test("Boards support creation, partial updates, archive filters, and search")
    func boardLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let created = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateBoardRequest(
                            name: "Product roadmap",
                            slug: "product-roadmap",
                            description: "Plan the next release"
                        )
                    )
                }
            )
            #expect(created.status == .created)
            let board = try created.content.decode(BoardResponse.self)

            let updated = try await jsonRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/boards/\(board.id)",
                cookie: session.cookie,
                json: #"{"description":null,"isArchived":true}"#
            )
            #expect(updated.status == .ok)
            let archivedBoard = try updated.content.decode(BoardResponse.self)
            #expect(archivedBoard.name == "Product roadmap")
            #expect(archivedBoard.description == nil)
            #expect(archivedBoard.isArchived)

            let search = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards?q=roadmap&archived=true",
                headers: ["Cookie": session.cookie]
            )
            let matches = try search.content.decode([BoardSummaryResponse].self)
            #expect(matches.map(\.id) == [board.id])
        }
    }

    @Test("Tasks support detail reads, filters, search, and partial updates")
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
                            title: "Publish release notes",
                            description: "Include the new REST API",
                            status: .backlog,
                            priority: .high,
                            labels: ["API", "api"],
                            dueAt: nil
                        )
                    )
                }
            )
            #expect(created.status == .created)
            let task = try created.content.decode(TaskResponse.self)
            #expect(task.labels == ["API"])
            #expect(task.publicID.count == 6)

            let detail = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(task.id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(detail.status == .ok)
            #expect(try detail.content.decode(TaskResponse.self).boardName == "My board")

            let updated = try await jsonRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/tasks/\(task.id)",
                cookie: session.cookie,
                json: #"{"title":"Ship release notes","description":null,"isArchived":true}"#
            )
            #expect(updated.status == .ok)
            let archivedTask = try updated.content.decode(TaskResponse.self)
            #expect(archivedTask.title == "Ship release notes")
            #expect(archivedTask.description == nil)
            #expect(archivedTask.priority == .high)
            #expect(archivedTask.isArchived)

            let search = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/search?q=release&priority=high&archived=true",
                headers: ["Cookie": session.cookie]
            )
            #expect(search.status == .ok)
            let matches = try search.content.decode(Page<TaskResponse>.self)
            #expect(matches.items.map(\.id) == [task.id])
        }
    }

    @Test("Task writes enforce board roles")
    func taskWritesEnforceBoardRoles() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let viewer = try await register(on: app)
            try await BoardMember(
                boardID: owner.boardID,
                userID: viewer.userID,
                role: .viewer
            ).create(on: app.db)
            let task = Task(
                boardID: owner.boardID,
                title: "Private task",
                position: 1_000,
                creatorID: owner.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()

            let detail = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(taskID)",
                headers: ["Cookie": viewer.cookie]
            )
            #expect(detail.status == .ok)

            let update = try await jsonRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/tasks/\(taskID)",
                cookie: viewer.cookie,
                json: #"{"title":"Unauthorized change"}"#
            )
            #expect(update.status == .notFound)
            #expect(try #require(try await Task.find(taskID, on: app.db)).title == "Private task")
        }
    }

    /// Sends raw JSON so tests can verify the difference between a missing field
    /// and an explicit null, which a synthesized optional request cannot represent.
    private func jsonRequest(
        app: Application,
        method: HTTPMethod,
        path: String,
        cookie: String,
        json: String
    ) async throws -> TestingHTTPResponse {
        try await app.testing().sendRequest(
            method,
            path,
            headers: [
                "Cookie": cookie,
                "Content-Type": "application/json",
            ],
            body: ByteBufferAllocator().buffer(string: json)
        )
    }
}
