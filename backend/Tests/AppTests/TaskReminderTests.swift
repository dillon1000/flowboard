@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Task reminders")
struct TaskReminderTests {
    @Test("A user can manage up to three pending reminders")
    func reminderLifecycle() async throws {
        try await withApp(configure: configure) { app in
            app.notificationConfiguration = testConfiguration
            let session = try await register(on: app)
            let task = Task(
                boardID: session.boardID,
                title: "Submit the report",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()

            for hours in 1...3 {
                let response = try await app.testing().sendRequest(
                    .POST,
                    "api/v1/tasks/\(taskID)/reminders",
                    headers: ["Cookie": session.cookie],
                    beforeRequest: { request in
                        try request.content.encode(
                            CreateTaskReminderRequest(
                                remindAt: Date(timeIntervalSinceNow: TimeInterval(hours * 3_600)),
                                timeZone: "America/Chicago"
                            )
                        )
                    }
                )
                #expect(response.status == .created)
            }

            let rejected = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/reminders",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateTaskReminderRequest(
                            remindAt: Date(timeIntervalSinceNow: 14_400),
                            timeZone: "America/Chicago"
                        )
                    )
                }
            )
            #expect(rejected.status == .conflict)

            let list = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(taskID)/reminders",
                headers: ["Cookie": session.cookie]
            )
            let reminders = try list.content.decode([TaskReminderResponse].self)
            #expect(reminders.count == 3)

            let deleted = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/tasks/\(taskID)/reminders/\(reminders[0].id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(deleted.status == .noContent)
            #expect(
                try await TaskReminder.query(on: app.db)
                    .filter(\.$task.$id == taskID)
                    .count() == 2
            )
        }
    }

    @Test("A due reminder enters the outbox once")
    func dueReminderEnqueue() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let task = Task(
                boardID: session.boardID,
                title: "Study chapter six",
                position: 1_000,
                dueAt: Date(timeIntervalSinceNow: 86_400),
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let reminder = TaskReminder(
                taskID: try task.requireID(),
                userID: session.userID,
                remindAt: Date(timeIntervalSinceNow: -60),
                timeZoneIdentifier: "America/Chicago"
            )
            try await reminder.create(on: app.db)

            await TaskReminderService.enqueueDueReminders(
                configuration: testConfiguration,
                database: app.db,
                logger: app.logger
            )
            await TaskReminderService.enqueueDueReminders(
                configuration: testConfiguration,
                database: app.db,
                logger: app.logger
            )

            let events = try await NotificationOutbox.query(on: app.db).all()
            let queuedReminder = try #require(try await TaskReminder.find(reminder.requireID(), on: app.db))
            #expect(events.count == 1)
            #expect(events[0].eventType == "task_reminder")
            #expect(events[0].payload["taskTitle"] == "Study chapter six")
            #expect(queuedReminder.queuedAt != nil)
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
