@testable import App
import Fluent
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting

@Suite("Canvas managed fields and grades")
struct CanvasManagedFieldsTests {
    @Test("Canvas-linked academic fields and deletions return conflict")
    func managedFieldsAndDisconnect() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let linked = try await createLinkedRecords(session: session, on: app)
            linked.course.syncArchived = true
            linked.assignment.syncArchived = true
            try await linked.course.update(on: app.db)
            try await linked.assignment.update(on: app.db)

            let boardName = try await rawJSONRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/boards/\(session.boardID)",
                cookie: session.cookie,
                json: #"{"name":"Local override"}"#
            )
            #expect(boardName.status == .conflict)

            let boardPlanning = try await rawJSONRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/boards/\(session.boardID)",
                cookie: session.cookie,
                json: #"{"description":"Local course notes","isArchived":true}"#
            )
            #expect(boardPlanning.status == .ok)
            #expect(try await Board.find(session.boardID, on: app.db)?.description == "Local course notes")
            #expect(try await Board.find(session.boardID, on: app.db)?.isArchived == true)
            #expect(
                try await CanvasCourseLink.find(linked.course.requireID(), on: app.db)?.syncArchived
                    == false
            )

            for academicJSON in [
                #"{"title":"Local title"}"#,
                #"{"description":"Local description"}"#,
                #"{"dueAt":"2026-09-02T00:00:00Z"}"#,
                #"{"dueTime":"12:30"}"#,
                #"{"gradeEarned":12}"#,
                #"{"gradePossible":20}"#,
            ] {
                let response = try await rawJSONRequest(
                    app: app,
                    method: .PATCH,
                    path: "api/v1/tasks/\(linked.task.requireID())",
                    cookie: session.cookie,
                    json: academicJSON
                )
                #expect(response.status == .conflict)
            }

            let planning = try await rawJSONRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/tasks/\(linked.task.requireID())",
                cookie: session.cookie,
                json: #"{"status":"in_progress","priority":"urgent","labels":["study"],"estimatedMinutes":60,"isArchived":true}"#
            )
            #expect(planning.status == .ok)
            let plannedTask = try #require(try await Task.find(linked.task.requireID(), on: app.db))
            #expect(plannedTask.title == "Canvas assignment")
            #expect(plannedTask.$description.value == "Canvas description")
            #expect(plannedTask.status == .inProgress)
            #expect(plannedTask.priority == .urgent)
            #expect(plannedTask.labels == ["study"])
            #expect(plannedTask.estimatedMinutes == 60)
            #expect(plannedTask.isArchived)
            #expect(
                try await CanvasAssignmentLink.find(linked.assignment.requireID(), on: app.db)?
                    .syncArchived == false
            )

            #expect(
                try await app.testing().sendRequest(
                    .DELETE,
                    "api/v1/tasks/\(linked.task.requireID())",
                    headers: ["Cookie": session.cookie]
                ).status == .conflict
            )
            #expect(
                try await app.testing().sendRequest(
                    .DELETE,
                    "api/v1/boards/\(session.boardID)",
                    headers: ["Cookie": session.cookie]
                ).status == .conflict
            )

            let disconnect = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/canvas-connections/\(linked.connection.requireID())",
                headers: ["Cookie": session.cookie]
            )
            #expect(disconnect.status == .noContent)
            #expect(try await Board.find(session.boardID, on: app.db) != nil)
            #expect(try await Task.find(linked.task.requireID(), on: app.db) != nil)
            #expect(try await CanvasCourseLink.query(on: app.db).count() == 0)
            #expect(try await CanvasAssignmentLink.query(on: app.db).count() == 0)

            let unlocked = try await rawJSONRequest(
                app: app,
                method: .PATCH,
                path: "api/v1/tasks/\(linked.task.requireID())",
                cookie: session.cookie,
                json: #"{"title":"Local title after disconnect"}"#
            )
            #expect(unlocked.status == .ok)
            #expect(
                try await app.testing().sendRequest(
                    .DELETE,
                    "api/v1/tasks/\(linked.task.requireID())",
                    headers: ["Cookie": session.cookie]
                ).status == .noContent
            )
            #expect(
                try await app.testing().sendRequest(
                    .DELETE,
                    "api/v1/boards/\(session.boardID)",
                    headers: ["Cookie": session.cookie]
                ).status == .noContent
            )
        }
    }

    @Test("Points possible can precede a score, and zero-point extra credit is valid")
    func gradeRules() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let ungraded = try await createTask(
                boardID: session.boardID,
                cookie: session.cookie,
                title: "Ungraded zero-point work",
                earned: nil,
                possible: 0,
                on: app
            )
            #expect(ungraded.status == .created)
            let ungradedTask = try ungraded.content.decode(TaskResponse.self)
            #expect(ungradedTask.gradeEarned == nil)
            #expect(ungradedTask.gradePossible == 0)
            let storedUngraded = try #require(try await Task.find(ungradedTask.id, on: app.db))
            #expect(try TaskCardContext(task: storedUngraded, assignee: nil).hasGrade == false)

            let extraCredit = try await createTask(
                boardID: session.boardID,
                cookie: session.cookie,
                title: "Extra credit",
                earned: 15,
                possible: 10,
                on: app
            )
            #expect(extraCredit.status == .created)
            let extraCreditTask = try extraCredit.content.decode(TaskResponse.self)
            #expect(extraCreditTask.gradeEarned == 15)
            #expect(extraCreditTask.gradePossible == 10)
            let storedExtraCredit = try #require(try await Task.find(extraCreditTask.id, on: app.db))
            #expect(try TaskCardContext(task: storedExtraCredit, assignee: nil).hasGrade)

            let missingPossible = try await createTask(
                boardID: session.boardID,
                cookie: session.cookie,
                title: "Invalid score",
                earned: 5,
                possible: nil,
                on: app
            )
            #expect(missingPossible.status == .unprocessableEntity)

            let negativePossible = try await createTask(
                boardID: session.boardID,
                cookie: session.cookie,
                title: "Invalid points",
                earned: nil,
                possible: -1,
                on: app
            )
            #expect(negativePossible.status == .unprocessableEntity)
        }
    }

    private func createLinkedRecords(
        session: (cookie: String, boardID: UUID, userID: UUID),
        on app: Application
    ) async throws -> (
        connection: CanvasConnection,
        course: CanvasCourseLink,
        task: Task,
        assignment: CanvasAssignmentLink
    ) {
        let connection = CanvasConnection(
            userID: session.userID,
            canvasOrigin: "https://canvas.example.edu",
            syncKeyHash: UUID().uuidString,
            syncKeyPrefix: "fcs_managed"
        )
        try await connection.create(on: app.db)
        let course = CanvasCourseLink(
            connectionID: try connection.requireID(),
            remoteCourseID: "101",
            boardID: session.boardID,
            canvasCourseURL: "https://canvas.example.edu/courses/101"
        )
        try await course.create(on: app.db)
        let task = Task(
            boardID: session.boardID,
            title: "Canvas assignment",
            description: "Canvas description",
            position: 1_000,
            dueAt: Date(timeIntervalSince1970: 1_788_134_400),
            dueTime: "10:00",
            gradeEarned: 8,
            gradePossible: 10,
            creatorID: session.userID
        )
        try await task.create(on: app.db)
        let assignment = CanvasAssignmentLink(
            courseLinkID: try course.requireID(),
            remoteAssignmentID: "501",
            taskID: try task.requireID(),
            canvasAssignmentURL: "https://canvas.example.edu/courses/101/assignments/501"
        )
        try await assignment.create(on: app.db)
        return (connection, course, task, assignment)
    }

    private func createTask(
        boardID: UUID,
        cookie: String,
        title: String,
        earned: Double?,
        possible: Double?,
        on app: Application
    ) async throws -> TestingHTTPResponse {
        try await app.testing().sendRequest(
            .POST,
            "api/v1/tasks",
            headers: ["Cookie": cookie],
            beforeRequest: { request in
                try request.content.encode(
                    CreateTaskRequest(
                        boardID: boardID,
                        title: title,
                        description: nil,
                        status: .backlog,
                        priority: .medium,
                        labels: [],
                        dueAt: nil,
                        gradeEarned: earned,
                        gradePossible: possible
                    )
                )
            }
        )
    }

    private func rawJSONRequest(
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
