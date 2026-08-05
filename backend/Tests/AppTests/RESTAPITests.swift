@testable import App
import Fluent
import Foundation
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
            let dueDate = Date(timeIntervalSince1970: 1_728_000_000)
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
                            dueAt: dueDate,
                            dueTime: "14:30",
                            estimatedMinutes: 90
                        )
                    )
                }
            )
            #expect(created.status == .created)
            let task = try created.content.decode(TaskResponse.self)
            #expect(task.labels == ["API"])
            #expect(task.publicID.count == 6)
            #expect(task.dueTime == "14:30")
            #expect(task.estimatedMinutes == 90)

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

            let oversizedPage = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks?per=101",
                headers: ["Cookie": session.cookie]
            )
            #expect(oversizedPage.status == .unprocessableEntity)
        }
    }

    @Test("Task descriptions accept the browser limit")
    func taskDescriptionLimit() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let accepted = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskRequest(
                            boardID: session.boardID,
                            title: "Long task description",
                            description: String(repeating: "a", count: 5_000),
                            status: .backlog,
                            priority: .medium,
                            labels: [],
                            dueAt: nil
                        )
                    )
                }
            )
            #expect(accepted.status == .created)

            let rejected = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskRequest(
                            boardID: session.boardID,
                            title: "Oversized task description",
                            description: String(repeating: "a", count: 5_001),
                            status: .backlog,
                            priority: .medium,
                            labels: [],
                            dueAt: nil
                        )
                    )
                }
            )
            #expect(rejected.status == .unprocessableEntity)
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

    @Test("Task collaboration resources support their full lifecycle")
    func taskCollaborationResources() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let task = Task(
                boardID: session.boardID,
                title: "Coordinate the release",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()

            let createdComment = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/comments",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(CreateTaskCommentRequest(body: "First draft"))
                }
            )
            #expect(createdComment.status == .created)
            let comment = try createdComment.content.decode(TaskCommentResponse.self)
            let updatedComment = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/tasks/\(taskID)/comments/\(comment.id)",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(CreateTaskCommentRequest(body: "Final draft"))
                }
            )
            #expect(try updatedComment.content.decode(TaskCommentResponse.self).body == "Final draft")

            var checklist: [TaskChecklistItemResponse] = []
            for title in ["Write notes", "Publish notes"] {
                let createdItem = try await app.testing().sendRequest(
                    .POST,
                    "api/v1/tasks/\(taskID)/checklist",
                    headers: ["Cookie": session.cookie],
                    beforeRequest: { request in
                        try request.content.encode(CreateChecklistItemRequest(title: title))
                    }
                )
                #expect(createdItem.status == .created)
                checklist.append(try createdItem.content.decode(TaskChecklistItemResponse.self))
            }
            let moved = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/checklist/\(checklist[1].id)/move",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(MoveChecklistItemRequest(targetIndex: 0))
                }
            )
            #expect(try moved.content.decode(TaskChecklistItemResponse.self).position == 1_000)
            let listedChecklist = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(taskID)/checklist",
                headers: ["Cookie": session.cookie]
            )
            #expect(
                try listedChecklist.content.decode([TaskChecklistItemResponse].self).map(\.title)
                    == ["Publish notes", "Write notes"]
            )

            let followed = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/followers/me",
                headers: ["Cookie": session.cookie]
            )
            #expect(followed.status == .created)
            let followedAgain = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/followers/me",
                headers: ["Cookie": session.cookie]
            )
            #expect(followedAgain.status == .ok)
            let followers = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(taskID)/followers",
                headers: ["Cookie": session.cookie]
            )
            #expect(try followers.content.decode([TaskFollowerResponse].self).count == 1)

            let deletedComment = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/tasks/\(taskID)/comments/\(comment.id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(deletedComment.status == .noContent)
        }
    }

    @Test("Board collaboration and configuration resources support their lifecycle")
    func boardCollaborationResources() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let invited = try await register(on: app)
            let invitedUser = try #require(try await User.find(invited.userID, on: app.db))

            let createdMember = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(owner.boardID)/members",
                headers: ["Cookie": owner.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateBoardMemberRequest(email: invitedUser.email, role: .editor)
                    )
                }
            )
            #expect(createdMember.status == .created)
            let member = try createdMember.content.decode(BoardMemberResponse.self)
            #expect(member.role == .editor)
            let members = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards/\(owner.boardID)/members",
                headers: ["Cookie": owner.cookie]
            )
            #expect(try members.content.decode([BoardMemberResponse].self).count == 2)

            let createdView = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(owner.boardID)/views",
                headers: ["Cookie": owner.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateBoardViewRequest(
                            name: "Release queue",
                            type: .gantt,
                            configuration: nil
                        )
                    )
                }
            )
            #expect(createdView.status == .created)
            let view = try createdView.content.decode(BoardViewResponse.self)
            #expect(view.type == .gantt)
            let updatedView = try await jsonRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/boards/\(owner.boardID)/views/\(view.id)",
                cookie: owner.cookie,
                json: #"{"name":"Launch queue","configuration":null}"#
            )
            #expect(try updatedView.content.decode(BoardViewResponse.self).name == "Launch queue")

            let createdTemplate = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(owner.boardID)/templates",
                headers: ["Cookie": owner.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskTemplateRequest(
                            name: "Release task",
                            title: "Prepare release",
                            description: "Use the checklist",
                            status: .backlog,
                            priority: .high,
                            labels: ["Release"],
                            isDefault: true
                        )
                    )
                }
            )
            #expect(createdTemplate.status == .created)
            let template = try createdTemplate.content.decode(TaskTemplateResponse.self)
            let instantiated = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(owner.boardID)/templates/\(template.id)/instantiate",
                headers: ["Cookie": invited.cookie]
            )
            #expect(instantiated.status == .created)
            let task = try instantiated.content.decode(TaskResponse.self)
            #expect(task.title == "Prepare release")
            #expect(task.creatorID == invited.userID)
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
