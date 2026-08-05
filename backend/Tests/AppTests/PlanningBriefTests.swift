@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Planning briefs")
struct PlanningBriefTests {
    @Test("Planning briefs use local delivery time and enter the outbox once")
    func localDeliveryAndDeduplication() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let user = try #require(try await User.find(session.userID, on: app.db))
            user.timeZoneIdentifier = "America/Chicago"
            user.dailyBriefEnabled = true
            user.weeklyPlanningPromptEnabled = true
            user.planningEmailHour = 7
            try await user.update(on: app.db)

            let task = Task(
                boardID: session.boardID,
                title: "Prepare final presentation",
                position: 1_000,
                dueAt: try instant("2026-08-03T12:00:00Z"),
                estimatedMinutes: 90,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            try await StudySession(
                taskID: task.requireID(),
                userID: session.userID,
                scheduledDate: "2026-08-03",
                plannedMinutes: 30
            ).create(on: app.db)

            await PlanningBriefService.enqueueDueBriefs(
                configuration: testConfiguration,
                database: app.db,
                logger: app.logger,
                referenceDate: try instant("2026-08-03T11:59:00Z")
            )
            #expect(try await NotificationOutbox.query(on: app.db).count() == 0)

            let deliveryTime = try instant("2026-08-03T12:15:00Z")
            await PlanningBriefService.enqueueDueBriefs(
                configuration: testConfiguration,
                database: app.db,
                logger: app.logger,
                referenceDate: deliveryTime
            )
            await PlanningBriefService.enqueueDueBriefs(
                configuration: testConfiguration,
                database: app.db,
                logger: app.logger,
                referenceDate: deliveryTime
            )

            let events = try await NotificationOutbox.query(on: app.db)
                .sort(\.$eventType, .ascending)
                .all()
            #expect(events.count == 2)
            let daily = try #require(events.first { $0.eventType == "daily_brief" })
            #expect(daily.payload["dateLabel"] == "Monday, August 3")
            #expect(daily.payload["studySessionCount"] == "1")
            #expect(daily.payload["plannedTime"] == "30 min")
            #expect(daily.payload["deadlineCount"] == "1")
            let weekly = try #require(events.first { $0.eventType == "weekly_planning_prompt" })
            #expect(weekly.payload["unplannedTaskCount"] == "1")
            #expect(weekly.payload["remainingTime"] == "1h")
        }
    }

    private var testConfiguration: NotificationConfiguration {
        NotificationConfiguration(
            workerURL: URI(string: "https://email.example/v1/notifications"),
            sharedSecret: String(repeating: "x", count: 32),
            publicAppURL: "https://app.example"
        )
    }
}

private func instant(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
}
