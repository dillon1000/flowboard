@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Canvas sync models")
struct CanvasModelTests {
    @Test("Connections and links store remote identity without owning local records")
    func relationshipsAndDisconnect() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let connection = CanvasConnection(
                userID: session.userID,
                canvasOrigin: "https://canvas.example.edu",
                syncKeyHash: "hash-one",
                syncKeyPrefix: "fcs_example"
            )
            try await connection.create(on: app.db)
            let course = CanvasCourseLink(
                connectionID: try connection.requireID(),
                remoteCourseID: "101",
                boardID: session.boardID,
                canvasCourseURL: "https://canvas.example.edu/courses/101",
                courseCode: "BIO-101",
                termName: "Fall 2026",
                currentScore: 92.5,
                currentGrade: "A-"
            )
            try await course.create(on: app.db)
            let task = Task(
                boardID: session.boardID,
                title: "Lab report",
                position: 1_000,
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

            #expect(course.courseCode == "BIO-101")
            #expect(course.currentScore == 92.5)
            #expect(assignment.consecutiveMissingCount == 0)
            #expect(assignment.canvasControlsCompletion == false)

            try await connection.delete(on: app.db)

            #expect(try await CanvasCourseLink.query(on: app.db).count() == 0)
            #expect(try await CanvasAssignmentLink.query(on: app.db).count() == 0)
            #expect(try await Board.find(session.boardID, on: app.db) != nil)
            #expect(try await Task.find(task.requireID(), on: app.db) != nil)
        }
    }

    @Test("Connection, course, and assignment identities are unique")
    func uniqueRemoteIdentity() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let connection = CanvasConnection(
                userID: session.userID,
                canvasOrigin: "https://canvas.example.edu",
                syncKeyHash: "hash-one",
                syncKeyPrefix: "fcs_example"
            )
            try await connection.create(on: app.db)

            let duplicateConnection = CanvasConnection(
                userID: session.userID,
                canvasOrigin: "https://canvas.example.edu",
                syncKeyHash: "hash-two",
                syncKeyPrefix: "fcs_second"
            )
            await #expect(throws: (any Error).self) {
                try await duplicateConnection.create(on: app.db)
            }

            let board = try await WorkspaceService.createBoard(
                name: "Canvas course",
                slug: "canvas-course",
                ownerID: session.userID,
                on: app.db
            )
            let course = CanvasCourseLink(
                connectionID: try connection.requireID(),
                remoteCourseID: "101",
                boardID: try board.requireID(),
                canvasCourseURL: "https://canvas.example.edu/courses/101"
            )
            try await course.create(on: app.db)
            let duplicateCourse = CanvasCourseLink(
                connectionID: try connection.requireID(),
                remoteCourseID: "101",
                boardID: session.boardID,
                canvasCourseURL: "https://canvas.example.edu/courses/101"
            )
            await #expect(throws: (any Error).self) {
                try await duplicateCourse.create(on: app.db)
            }

            let task = Task(
                boardID: try board.requireID(),
                title: "First assignment",
                position: 1_000,
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

            let secondTask = Task(
                boardID: try board.requireID(),
                title: "Second assignment",
                position: 2_000,
                creatorID: session.userID
            )
            try await secondTask.create(on: app.db)
            let duplicateAssignment = CanvasAssignmentLink(
                courseLinkID: try course.requireID(),
                remoteAssignmentID: "501",
                taskID: try secondTask.requireID(),
                canvasAssignmentURL: "https://canvas.example.edu/courses/101/assignments/501"
            )
            await #expect(throws: (any Error).self) {
                try await duplicateAssignment.create(on: app.db)
            }
        }
    }
}
