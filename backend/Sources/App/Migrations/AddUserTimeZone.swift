import Fluent

/// Stores the IANA zone that controls each user's local planning day. UTC keeps
/// existing accounts valid until sign-in or profile settings supplies a zone.
struct AddUserTimeZone: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("time_zone", .string, .required, .sql(.default("UTC")))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("time_zone")
            .update()
    }
}
