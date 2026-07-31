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
            #expect(response.headers.first(name: .flowboardServerName) == "flowboard-server")
            #expect(response.headers.first(name: .flowboardServerVersion) == "0.1.0")
            let serverTime = try #require(response.headers.first(name: .flowboardServerTime))
            #expect(ISO8601DateFormatter().date(from: serverTime) != nil)
        }
    }

    @Test("Unknown browser routes render the not found page")
    func unknownBrowserRouteRendersNotFoundPage() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "missing-page")

            #expect(response.status == .notFound)
            #expect(response.headers.contentType == .html)
            expectContains(response.body.string, "This card isn’t on the board.")
            expectContains(response.body.string, "focalboard-wordmark.webp")
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

    @Test("Auth pages and the app sidebar show the build signature")
    func pagesShowBuildSignature() async throws {
        try await withApp(configure: configure) { app in
            for path in ["login", "register"] {
                let response = try await app.testing().sendRequest(.GET, path)

                #expect(response.status == .ok)
                expectContains(response.body.string, "Built with love and")
                expectContains(response.body.string, #"src="/swift.svg""#)
                expectContains(response.body.string, "in McKinney, Texas.")
            }

            let session = try await register(on: app)
            let appPage = try await app.testing().sendRequest(
                .GET,
                "app",
                headers: ["Cookie": session.cookie]
            )

            #expect(appPage.status == .ok)
            expectContains(appPage.body.string, "Built with love and")
            expectContains(appPage.body.string, #"src="/swift.svg""#)
            expectContains(appPage.body.string, "in McKinney, Texas.")
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
            let createdTask = try created.content.decode(TaskResponse.self)
            let storedTask = try #require(try await Task.find(createdTask.id, on: app.db))
            #expect(storedTask.$creator.id == session.userID)

            let legacyTaskPage = try await app.testing().sendRequest(
                .GET,
                "app/tasks/\(createdTask.id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(legacyTaskPage.status == .movedPermanently)
            #expect(legacyTaskPage.headers.first(name: .location) == storedTask.browserPath)

            let taskPage = try await app.testing().sendRequest(
                .GET,
                String(storedTask.browserPath.dropFirst()),
                headers: ["Cookie": session.cookie]
            )
            #expect(taskPage.status == .ok)
            expectContains(
                taskPage.body.string,
                #"<a href="/app/boards/\#(session.boardID)">My board</a>"#
            )
            expectContains(taskPage.body.string, "<dt>Creator</dt>")
            expectContains(taskPage.body.string, "<dd>Test User</dd>")
            expectContains(taskPage.body.string, ">Promote</span>")
            expectContains(
                taskPage.body.string,
                #"/app/tasks/\#(createdTask.id)/status"#
            )

            let csrfMarker = #"name="csrf-token" content=""#
            let csrfStart = try #require(taskPage.body.string.range(of: csrfMarker)?.upperBound)
            let csrfEnd = try #require(
                taskPage.body.string[csrfStart...].firstIndex(of: "\"")
            )
            let csrfToken = String(taskPage.body.string[csrfStart..<csrfEnd])
            let promoted = try await app.testing().sendRequest(
                .POST,
                "app/tasks/\(createdTask.id)/status",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(["status": "done"], as: .urlEncodedForm)
                }
            )
            #expect(promoted.status == .seeOther)
            #expect(promoted.headers.first(name: .location) == storedTask.browserPath)
            let promotedTask = try #require(try await Task.find(createdTask.id, on: app.db))
            #expect(promotedTask.status == .done)

            let listed = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks?page=1&per=25",
                headers: ["Cookie": session.cookie]
            )
            #expect(listed.status == .ok)
            expectContains(listed.body.string, "\"boardName\":\"My board\"")
        }
    }

    @Test("An archived task can be found and restored")
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

            let detailPage = try await app.testing().sendRequest(
                .GET,
                String(task.browserPath.dropFirst()),
                headers: ["Cookie": session.cookie]
            )
            let csrfMarker = #"name="csrf-token" content=""#
            let csrfStart = try #require(detailPage.body.string.range(of: csrfMarker)?.upperBound)
            let csrfEnd = try #require(
                detailPage.body.string[csrfStart...].firstIndex(of: "\"")
            )
            let csrfToken = String(detailPage.body.string[csrfStart..<csrfEnd])

            let archived = try await app.testing().sendRequest(
                .POST,
                "app/tasks/\(taskID)/archive",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ]
            )
            #expect(archived.status == .seeOther)
            #expect(try #require(try await Task.find(taskID, on: app.db)).isArchived)

            let activeTasks = try await app.testing().sendRequest(
                .GET,
                "app/tasks",
                headers: ["Cookie": session.cookie]
            )
            #expect(!activeTasks.body.string.contains("Recover the archived task"))

            let archivedTasks = try await app.testing().sendRequest(
                .GET,
                "app/tasks/archived",
                headers: ["Cookie": session.cookie]
            )
            #expect(archivedTasks.status == .ok)
            expectContains(archivedTasks.body.string, "Archived tasks")
            expectContains(archivedTasks.body.string, "Recover the archived task")
            expectContains(archivedTasks.body.string, ">Restore</button>")

            let restored = try await app.testing().sendRequest(
                .POST,
                "app/tasks/\(taskID)/archive",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ]
            )
            #expect(restored.status == .seeOther)
            #expect(restored.headers.first(name: .location) == task.browserPath)
            #expect(!(try #require(try await Task.find(taskID, on: app.db))).isArchived)
        }
    }

    @Test("Task pages use a title slug with a stable case-insensitive key")
    func taskPagesUseFriendlySlugs() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let task = Task(
                publicID: "a1b2c3",
                boardID: session.boardID,
                title: "Add 2 way Focalboard <--> Thinkspace Sync",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let originalPath = "/app/tasks/add-2-way-focalboard-thinkspace-sync-a1b2c3"
            #expect(task.browserPath == originalPath)

            let canonical = try await app.testing().sendRequest(
                .GET,
                String(originalPath.dropFirst()),
                headers: ["Cookie": session.cookie]
            )
            #expect(canonical.status == .ok)
            expectContains(canonical.body.string, "Add 2 way Focalboard")

            let uppercase = try await app.testing().sendRequest(
                .GET,
                "app/tasks/ADD-2-WAY-FOCALBOARD-THINKSPACE-SYNC-A1B2C3",
                headers: ["Cookie": session.cookie]
            )
            #expect(uppercase.status == .movedPermanently)
            #expect(uppercase.headers.first(name: .location) == originalPath)

            task.title = "Finish Thinkspace sync"
            try await task.update(on: app.db)
            let renamedPath = "/app/tasks/finish-thinkspace-sync-a1b2c3"
            let oldSlug = try await app.testing().sendRequest(
                .GET,
                String(originalPath.dropFirst()),
                headers: ["Cookie": session.cookie]
            )
            #expect(oldSlug.status == .movedPermanently)
            #expect(oldSlug.headers.first(name: .location) == renamedPath)
        }
    }

}
