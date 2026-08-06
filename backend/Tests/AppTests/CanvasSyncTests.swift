@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Canvas connection and sync")
struct CanvasSyncTests {
    @Test("Session routes create, normalize, rotate, revoke, and enforce ownership")
    func connectionLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let other = try await register(on: app)
            let created = try await createCanvasConnection(
                cookie: owner.cookie,
                origin: "https://CANVAS.Example.edu/",
                on: app
            )
            #expect(created.connection.canvasOrigin == canvasOrigin)
            #expect(created.syncKey.hasPrefix("fcs_"))
            #expect(created.syncKey.count == 68)
            #expect(created.connection.keyPrefix == String(created.syncKey.prefix(12)))

            let stored = try #require(
                try await CanvasConnection.find(created.connection.id, on: app.db)
            )
            #expect(stored.syncKeyHash == CanvasCredentialService.hash(created.syncKey))
            #expect(stored.syncKeyHash != created.syncKey)

            let list = try await app.testing().sendRequest(
                .GET,
                "api/v1/auth/canvas-connections",
                headers: ["Cookie": owner.cookie]
            )
            #expect(list.status == .ok)
            #expect(try list.content.decode([CanvasConnectionResponse].self).count == 1)
            #expect(!list.body.string.contains(created.syncKey))

            let wrongOwner = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/canvas-connections/\(created.connection.id)/rotate",
                headers: ["Cookie": other.cookie]
            )
            #expect(wrongOwner.status == .notFound)

            let rotatedResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/canvas-connections/\(created.connection.id)/rotate",
                headers: ["Cookie": owner.cookie]
            )
            #expect(rotatedResponse.status == .ok)
            let rotated = try rotatedResponse.content.decode(CreatedCanvasConnectionResponse.self)
            #expect(rotated.syncKey != created.syncKey)

            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/integrations/canvas/status",
                    headers: ["Authorization": "Bearer \(created.syncKey)"]
                ).status == .unauthorized
            )
            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/integrations/canvas/status",
                    headers: ["Authorization": "Bearer \(rotated.syncKey)"]
                ).status == .ok
            )
            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/boards",
                    headers: ["Authorization": "Bearer \(rotated.syncKey)"]
                ).status == .unauthorized
            )

            let disconnected = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/canvas-connections/\(created.connection.id)",
                headers: ["Cookie": owner.cookie]
            )
            #expect(disconnected.status == .noContent)
            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/integrations/canvas/status",
                    headers: ["Authorization": "Bearer \(rotated.syncKey)"]
                ).status == .unauthorized
            )
        }
    }

    @Test("A full snapshot creates a course, standard views, and one Canvas-managed task")
    func initialImportDuplicateAndStale() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let user = try #require(try await User.find(session.userID, on: app.db))
            user.timeZoneIdentifier = "America/Chicago"
            try await user.update(on: app.db)
            let connection = try await createCanvasConnection(cookie: session.cookie, on: app)
            let snapshot = try canvasSnapshot(
                snapshotID: "snapshot-1",
                capturedAt: "2026-08-06T12:00:00Z",
                submission: CanvasSubmissionSnapshot(
                    workflowState: "submitted",
                    grade: nil,
                    score: nil,
                    submittedAt: try canvasDate("2026-08-06T01:00:00Z"),
                    late: false,
                    missing: false,
                    excused: false,
                    redoRequested: false
                )
            )

            let response = try await sendCanvasSnapshot(
                snapshot,
                key: connection.syncKey,
                on: app
            )
            #expect(response.status == .ok)
            let result = try response.content.decode(CanvasSyncResponse.self)
            #expect(result.duplicate == false)
            #expect(result.counts.coursesCreated == 1)
            #expect(result.counts.assignmentsCreated == 1)
            #expect(result.counts.assignmentsCompleted == 1)

            let courseLink = try #require(
                try await CanvasCourseLink.query(on: app.db)
                    .filter(\.$connection.$id == connection.connection.id)
                    .with(\.$board)
                    .first()
            )
            #expect(courseLink.courseCode == "BIO-101")
            #expect(courseLink.termName == "Fall 2026")
            #expect(courseLink.currentScore == 93.5)
            #expect(courseLink.currentGrade == "A")
            #expect(courseLink.board.name == "Biology")
            #expect(
                try await BoardView.query(on: app.db)
                    .filter(\.$board.$id == courseLink.board.requireID())
                    .count() == 5
            )

            let assignmentLink = try #require(
                try await CanvasAssignmentLink.query(on: app.db)
                    .filter(\.$courseLink.$id == courseLink.requireID())
                    .with(\.$task)
                    .first()
            )
            let importedTask = try #require(assignmentLink.$task.value)
            #expect(importedTask.title == "Lab report")
            #expect(importedTask.$description.value == "Write the report.")
            #expect(importedTask.dueTime == "20:30")
            #expect(importedTask.gradePossible == 0)
            #expect(importedTask.status == .done)
            #expect(assignmentLink.statusBeforeCanvasCompletion == "backlog")
            #expect(assignmentLink.canvasControlsCompletion)
            #expect(
                ISO8601DateFormatter().string(from: try #require(importedTask.dueAt))
                    == "2026-08-31T00:00:00Z"
            )

            importedTask.estimatedMinutes = 90
            try await importedTask.update(on: app.db)
            let duplicateResponse = try await sendCanvasSnapshot(
                snapshot,
                key: connection.syncKey,
                on: app
            )
            let duplicate = try duplicateResponse.content.decode(CanvasSyncResponse.self)
            #expect(duplicate.duplicate)
            #expect(duplicate.counts.coursesUpdated == 0)
            #expect(
                try await Task.find(importedTask.requireID(), on: app.db)?.estimatedMinutes == 90
            )

            let stale = try canvasSnapshot(
                snapshotID: "snapshot-stale",
                capturedAt: "2026-08-06T11:59:59Z",
                courseName: "Stale name"
            )
            #expect(
                try await sendCanvasSnapshot(stale, key: connection.syncKey, on: app).status
                    == .conflict
            )
            #expect(
                try await Board.find(courseLink.board.requireID(), on: app.db)?.name == "Biology"
            )
        }
    }

    @Test("Updates preserve planning fields and apply completion and reopen rules")
    func updatesAndWorkflowTransitions() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let connection = try await createCanvasConnection(cookie: session.cookie, on: app)
            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(snapshotID: "workflow-1", capturedAt: "2026-08-06T12:00:00Z"),
                key: connection.syncKey,
                on: app
            )
            let link = try #require(
                try await CanvasAssignmentLink.query(on: app.db).with(\.$task).first()
            )
            let task = link.task
            task.priority = .urgent
            task.labels = ["study"]
            task.estimatedMinutes = 75
            task.position = 9_000
            task.startAt = try canvasDate("2026-08-15T00:00:00Z")
            try await task.update(on: app.db)

            let submitted = try canvasSnapshot(
                snapshotID: "workflow-2",
                capturedAt: "2026-08-06T12:01:00Z",
                assignmentName: "Updated lab report",
                submission: CanvasSubmissionSnapshot(
                    workflowState: "submitted",
                    grade: nil,
                    score: nil,
                    submittedAt: try canvasDate("2026-08-06T12:00:30Z"),
                    late: true,
                    missing: false,
                    excused: false,
                    redoRequested: false
                )
            )
            _ = try await sendCanvasSnapshot(submitted, key: connection.syncKey, on: app)
            let afterSubmitted = try #require(try await Task.find(task.requireID(), on: app.db))
            #expect(afterSubmitted.status == .done)
            #expect(afterSubmitted.title == "Updated lab report")
            #expect(afterSubmitted.priority == .urgent)
            #expect(afterSubmitted.labels == ["study"])
            #expect(afterSubmitted.estimatedMinutes == 75)
            #expect(afterSubmitted.position == 9_000)
            #expect(afterSubmitted.startAt == task.startAt)

            let reopened = try canvasSnapshot(
                snapshotID: "workflow-3",
                capturedAt: "2026-08-06T12:02:00Z",
                submission: CanvasSubmissionSnapshot(
                    workflowState: "unsubmitted",
                    grade: nil,
                    score: nil,
                    submittedAt: nil,
                    late: false,
                    missing: true,
                    excused: false,
                    redoRequested: false
                )
            )
            let reopenedResponse = try await sendCanvasSnapshot(
                reopened,
                key: connection.syncKey,
                on: app
            )
            #expect(
                try reopenedResponse.content.decode(CanvasSyncResponse.self)
                    .counts.assignmentsReopened == 1
            )
            #expect(try await Task.find(task.requireID(), on: app.db)?.status == .backlog)

            for (index, state) in ["graded", "pending_review"].enumerated() {
                let completeMinute = 3 + index * 2
                let completed = try canvasSnapshot(
                    snapshotID: "workflow-complete-\(index)",
                    capturedAt: "2026-08-06T12:0\(completeMinute):00Z",
                    submission: CanvasSubmissionSnapshot(
                        workflowState: state,
                        grade: "10",
                        score: 10,
                        submittedAt: try canvasDate("2026-08-06T12:00:30Z"),
                        late: false,
                        missing: false,
                        excused: false,
                        redoRequested: false
                    )
                )
                _ = try await sendCanvasSnapshot(completed, key: connection.syncKey, on: app)
                #expect(try await Task.find(task.requireID(), on: app.db)?.status == .done)

                let reassigned = try canvasSnapshot(
                    snapshotID: "workflow-redo-\(index)",
                    capturedAt: "2026-08-06T12:0\(completeMinute + 1):00Z",
                    submission: CanvasSubmissionSnapshot(
                        workflowState: state,
                        grade: nil,
                        score: nil,
                        submittedAt: nil,
                        late: false,
                        missing: false,
                        excused: false,
                        redoRequested: true
                    )
                )
                _ = try await sendCanvasSnapshot(reassigned, key: connection.syncKey, on: app)
                #expect(try await Task.find(task.requireID(), on: app.db)?.status == .backlog)
            }

            let excused = try canvasSnapshot(
                snapshotID: "workflow-excused",
                capturedAt: "2026-08-06T12:10:00Z",
                submission: CanvasSubmissionSnapshot(
                    workflowState: "unsubmitted",
                    grade: "EX",
                    score: nil,
                    submittedAt: nil,
                    late: false,
                    missing: false,
                    excused: true,
                    redoRequested: false
                )
            )
            _ = try await sendCanvasSnapshot(excused, key: connection.syncKey, on: app)
            #expect(try await Task.find(task.requireID(), on: app.db)?.status == .done)
        }
    }

    @Test("Two missing snapshots archive records and only sync archives reverse")
    func missingAndArchiveRules() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let connection = try await createCanvasConnection(cookie: session.cookie, on: app)
            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(snapshotID: "missing-1", capturedAt: "2026-08-06T12:00:00Z"),
                key: connection.syncKey,
                on: app
            )
            let course = try #require(
                try await CanvasCourseLink.query(on: app.db).with(\.$board).first()
            )
            let assignment = try #require(
                try await CanvasAssignmentLink.query(on: app.db).with(\.$task).first()
            )

            let noAssignments = try canvasSnapshot(
                snapshotID: "missing-2",
                capturedAt: "2026-08-06T12:01:00Z",
                includeAssignment: false
            )
            _ = try await sendCanvasSnapshot(noAssignments, key: connection.syncKey, on: app)
            #expect(!assignment.task.isArchived)
            #expect(
                try await CanvasAssignmentLink.find(assignment.requireID(), on: app.db)?
                    .consecutiveMissingCount == 1
            )
            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(
                    snapshotID: "missing-3",
                    capturedAt: "2026-08-06T12:02:00Z",
                    includeAssignment: false
                ),
                key: connection.syncKey,
                on: app
            )
            #expect(try await Task.find(assignment.task.requireID(), on: app.db)?.isArchived == true)

            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(snapshotID: "missing-4", capturedAt: "2026-08-06T12:03:00Z"),
                key: connection.syncKey,
                on: app
            )
            #expect(try await Task.find(assignment.task.requireID(), on: app.db)?.isArchived == false)

            let manuallyArchivedTask = try #require(
                try await Task.find(assignment.task.requireID(), on: app.db)
            )
            manuallyArchivedTask.isArchived = true
            try await manuallyArchivedTask.update(on: app.db)
            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(snapshotID: "missing-5", capturedAt: "2026-08-06T12:04:00Z"),
                key: connection.syncKey,
                on: app
            )
            #expect(try await Task.find(manuallyArchivedTask.requireID(), on: app.db)?.isArchived == true)

            let noCourses = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "missing-course-1",
                canvasOrigin: canvasOrigin,
                capturedAt: try canvasDate("2026-08-06T12:05:00Z"),
                courses: []
            )
            _ = try await sendCanvasSnapshot(noCourses, key: connection.syncKey, on: app)
            #expect(!course.board.isArchived)
            let noCoursesAgain = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "missing-course-2",
                canvasOrigin: canvasOrigin,
                capturedAt: try canvasDate("2026-08-06T12:06:00Z"),
                courses: []
            )
            _ = try await sendCanvasSnapshot(noCoursesAgain, key: connection.syncKey, on: app)
            #expect(try await Board.find(course.board.requireID(), on: app.db)?.isArchived == true)

            _ = try await sendCanvasSnapshot(
                try canvasSnapshot(snapshotID: "missing-course-3", capturedAt: "2026-08-06T12:07:00Z"),
                key: connection.syncKey,
                on: app
            )
            #expect(try await Board.find(course.board.requireID(), on: app.db)?.isArchived == false)
        }
    }

    @Test("Invalid origins, duplicate IDs, URLs, and strings make no writes")
    func payloadValidationAndNoPartialWrites() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let connection = try await createCanvasConnection(cookie: session.cookie, on: app)
            let initialBoardCount = try await Board.query(on: app.db).count()

            let wrongOrigin = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "invalid-origin",
                canvasOrigin: "https://other.example.edu",
                capturedAt: try canvasDate("2026-08-06T12:00:00Z"),
                courses: []
            )
            #expect(
                try await sendCanvasSnapshot(wrongOrigin, key: connection.syncKey, on: app).status
                    == .forbidden
            )

            let course = try canvasCourse()
            let duplicateCourses = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "duplicate-courses",
                canvasOrigin: canvasOrigin,
                capturedAt: try canvasDate("2026-08-06T12:01:00Z"),
                courses: [course, course]
            )
            #expect(
                try await sendCanvasSnapshot(duplicateCourses, key: connection.syncKey, on: app).status
                    == .unprocessableEntity
            )

            let invalidURLCourse = CanvasCourseSnapshot(
                id: "101",
                name: "Biology",
                courseCode: nil,
                termName: nil,
                htmlURL: "http://canvas.example.edu/courses/101",
                currentScore: nil,
                currentGrade: nil,
                assignments: []
            )
            let invalidURL = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "invalid-url",
                canvasOrigin: canvasOrigin,
                capturedAt: try canvasDate("2026-08-06T12:02:00Z"),
                courses: [invalidURLCourse]
            )
            #expect(
                try await sendCanvasSnapshot(invalidURL, key: connection.syncKey, on: app).status
                    == .unprocessableEntity
            )

            let oversizedAssignment = CanvasAssignmentSnapshot(
                id: "501",
                name: "Lab report",
                descriptionText: String(repeating: "x", count: 5_001),
                htmlURL: "\(canvasOrigin)/courses/101/assignments/501",
                dueAt: nil,
                pointsPossible: 10,
                submission: nil
            )
            let oversizedCourse = CanvasCourseSnapshot(
                id: "101",
                name: "Biology",
                courseCode: nil,
                termName: nil,
                htmlURL: "\(canvasOrigin)/courses/101",
                currentScore: nil,
                currentGrade: nil,
                assignments: [oversizedAssignment]
            )
            let oversized = CanvasSyncSnapshotV1(
                version: 1,
                snapshotID: "oversized",
                canvasOrigin: canvasOrigin,
                capturedAt: try canvasDate("2026-08-06T12:03:00Z"),
                courses: [oversizedCourse]
            )
            #expect(
                try await sendCanvasSnapshot(oversized, key: connection.syncKey, on: app).status
                    == .unprocessableEntity
            )

            #expect(try await Board.query(on: app.db).count() == initialBoardCount)
            #expect(try await CanvasCourseLink.query(on: app.db).count() == 0)
            #expect(try await CanvasAssignmentLink.query(on: app.db).count() == 0)
        }
    }
}

private let canvasOrigin = "https://canvas.example.edu"

private func createCanvasConnection(
    cookie: String,
    origin: String = canvasOrigin,
    on app: Application
) async throws -> CreatedCanvasConnectionResponse {
    let response = try await app.testing().sendRequest(
        .POST,
        "api/v1/auth/canvas-connections",
        headers: ["Cookie": cookie],
        beforeRequest: { request in
            try request.content.encode(CreateCanvasConnectionRequest(canvasOrigin: origin))
        }
    )
    #expect(response.status == .created)
    return try response.content.decode(CreatedCanvasConnectionResponse.self)
}

private func sendCanvasSnapshot(
    _ snapshot: CanvasSyncSnapshotV1,
    key: String,
    on app: Application
) async throws -> TestingHTTPResponse {
    try await app.testing().sendRequest(
        .POST,
        "api/v1/integrations/canvas/sync",
        headers: ["Authorization": "Bearer \(key)"],
        beforeRequest: { request in
            try request.content.encode(snapshot)
        }
    )
}

private func canvasSnapshot(
    snapshotID: String,
    capturedAt: String,
    courseName: String = "Biology",
    assignmentName: String = "Lab report",
    submission: CanvasSubmissionSnapshot? = nil,
    includeAssignment: Bool = true
) throws -> CanvasSyncSnapshotV1 {
    CanvasSyncSnapshotV1(
        version: 1,
        snapshotID: snapshotID,
        canvasOrigin: canvasOrigin,
        capturedAt: try canvasDate(capturedAt),
        courses: [
            try canvasCourse(
                courseName: courseName,
                assignmentName: assignmentName,
                submission: submission,
                includeAssignment: includeAssignment
            ),
        ]
    )
}

private func canvasCourse(
    courseName: String = "Biology",
    assignmentName: String = "Lab report",
    submission: CanvasSubmissionSnapshot? = nil,
    includeAssignment: Bool = true
) throws -> CanvasCourseSnapshot {
    CanvasCourseSnapshot(
        id: "101",
        name: courseName,
        courseCode: "BIO-101",
        termName: "Fall 2026",
        htmlURL: "\(canvasOrigin)/courses/101",
        currentScore: 93.5,
        currentGrade: "A",
        assignments: includeAssignment
            ? [
                CanvasAssignmentSnapshot(
                    id: "501",
                    name: assignmentName,
                    descriptionText: "Write the report.",
                    htmlURL: "\(canvasOrigin)/courses/101/assignments/501",
                    dueAt: try canvasDate("2026-09-01T01:30:00Z"),
                    pointsPossible: 0,
                    submission: submission
                ),
            ]
            : []
    )
}

private func canvasDate(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
}
