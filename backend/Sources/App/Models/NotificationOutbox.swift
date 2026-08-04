import Fluent
import Foundation

enum NotificationOutboxStatus: String, Codable, Sendable {
    case pending
    case sent
    case failed
}

final class NotificationOutbox: Model, @unchecked Sendable {
    static let schema = "notification_outbox"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "deduplication_key")
    var deduplicationKey: String

    @Field(key: "event_type")
    var eventType: String

    @Field(key: "recipient")
    var recipient: String

    @Field(key: "payload")
    var payload: [String: String]

    @Field(key: "status")
    var statusValue: String

    @Field(key: "attempts")
    var attempts: Int

    @Field(key: "next_attempt_at")
    var nextAttemptAt: Date

    @OptionalField(key: "provider_message_id")
    var providerMessageID: String?

    @OptionalField(key: "last_error")
    var lastError: String?

    @OptionalField(key: "sent_at")
    var sentAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    var status: NotificationOutboxStatus {
        get { NotificationOutboxStatus(rawValue: statusValue) ?? .pending }
        set { statusValue = newValue.rawValue }
    }

    init() {}

    init(event: NotificationEvent) {
        self.id = event.eventID
        self.deduplicationKey = event.deduplicationKey
        self.eventType = event.type.rawValue
        self.recipient = event.recipient
        self.payload = event.data
        self.status = .pending
        self.attempts = 0
        self.nextAttemptAt = Date()
    }
}
