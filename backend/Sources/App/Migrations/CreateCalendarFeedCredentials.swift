import Fluent

/// Creates one revocable calendar feed credential per user. Both unique keys
/// prevent duplicate feeds or digest collisions during concurrent rotation.
struct CreateCalendarFeedCredentials: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(CalendarFeedCredential.schema)
            .id()
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("token_hash", .string, .required)
            .field("token_prefix", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(CalendarFeedCredential.schema).delete()
    }
}
