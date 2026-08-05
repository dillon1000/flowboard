@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Calendar feed")
struct CalendarFeedTests {
    @Test("A feed publishes planning events and supports rotation and revocation")
    func lifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let user = try #require(try await User.find(session.userID, on: app.db))
            user.timeZoneIdentifier = "America/Chicago"
            try await user.update(on: app.db)
            let task = Task(
                boardID: session.boardID,
                title: "Review notes, chapters 1;2 \\ practice",
                position: 1_000,
                dueAt: try calendarInstant("2026-08-03T12:00:00Z"),
                dueTime: "17:30",
                estimatedMinutes: 45,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            try await StudySession(
                taskID: task.requireID(),
                userID: session.userID,
                scheduledDate: "2026-08-02",
                plannedMinutes: 45
            ).create(on: app.db)

            let createdResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/calendar-feed",
                headers: ["Cookie": session.cookie]
            )
            #expect(createdResponse.status == .created)
            let created = try createdResponse.content.decode(CreatedCalendarFeedResponse.self)
            let credential = try #require(
                try await CalendarFeedCredential.query(on: app.db)
                    .filter(\.$user.$id == session.userID)
                    .first()
            )
            #expect(credential.tokenHash != created.token)
            #expect(credential.tokenPrefix == created.prefix)

            let feed = try await app.testing().sendRequest(
                .GET,
                "api/v1/calendar-feed/\(created.token)/calendar.ics"
            )
            #expect(feed.status == .ok)
            #expect(feed.headers.contentType?.type == "text")
            #expect(feed.headers.contentType?.subType == "calendar")
            let calendar = feed.body.string
            #expect(calendar.contains("BEGIN:VCALENDAR\r\n"))
            #expect(calendar.contains("DTSTART:20260803T223000Z"))
            #expect(calendar.contains("SUMMARY:Due: Review notes\\, chapters 1\\;2 \\\\ practice"))
            #expect(calendar.contains("DTSTART;VALUE=DATE:20260802"))
            #expect(calendar.contains("SUMMARY:Study: Review notes\\, chapters 1\\;2 \\\\ practice"))

            let rotatedResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/calendar-feed",
                headers: ["Cookie": session.cookie]
            )
            let rotated = try rotatedResponse.content.decode(CreatedCalendarFeedResponse.self)
            #expect(rotated.token != created.token)
            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/calendar-feed/\(created.token)/calendar.ics"
                ).status == .notFound
            )
            #expect(
                try await CalendarFeedCredential.query(on: app.db)
                    .filter(\.$user.$id == session.userID)
                    .count() == 1
            )

            let revoked = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/calendar-feed",
                headers: ["Cookie": session.cookie]
            )
            #expect(revoked.status == .noContent)
            #expect(
                try await app.testing().sendRequest(
                    .GET,
                    "api/v1/calendar-feed/\(rotated.token)/calendar.ics"
                ).status == .notFound
            )
        }
    }
}

private func calendarInstant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
}
