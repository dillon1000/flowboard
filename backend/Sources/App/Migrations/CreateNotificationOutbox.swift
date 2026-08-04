import Fluent

struct CreateNotificationOutbox: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(NotificationOutbox.schema)
            .id()
            .field("deduplication_key", .string, .required)
            .field("event_type", .string, .required)
            .field("recipient", .string, .required)
            .field("payload", .json, .required)
            .field("status", .string, .required)
            .field("attempts", .int, .required)
            .field("next_attempt_at", .datetime, .required)
            .field("provider_message_id", .string)
            .field("last_error", .string)
            .field("sent_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "deduplication_key")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(NotificationOutbox.schema).delete()
    }
}
