import Fluent
import Foundation
import Vapor

final class TaskReminder: Model, @unchecked Sendable {
    static let schema = "task_reminders"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: Task

    @Parent(key: "user_id")
    var user: User

    @Field(key: "remind_at")
    var remindAt: Date

    @Field(key: "time_zone")
    var timeZoneIdentifier: String

    @OptionalField(key: "queued_at")
    var queuedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(taskID: UUID, userID: UUID, remindAt: Date, timeZoneIdentifier: String) {
        self.$task.id = taskID
        self.$user.id = userID
        self.remindAt = remindAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

struct CreateTaskReminderRequest: Content, Validatable {
    let remindAt: Date
    let timeZone: String

    static func validations(_ validations: inout Validations) {
        validations.add("timeZone", as: String.self, is: .count(1...100))
    }
}

struct TaskReminderResponse: Content {
    let id: UUID
    let remindAt: Date
    let remindAtDisplay: String
    let timeZone: String

    init(reminder: TaskReminder) throws {
        self.id = try reminder.requireID()
        self.remindAt = reminder.remindAt
        self.timeZone = reminder.timeZoneIdentifier
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: reminder.timeZoneIdentifier)
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        self.remindAtDisplay = formatter.string(from: reminder.remindAt)
    }
}
