import Fluent

/// Creates user-owned API credentials. Only the digest and a short visible prefix
/// are stored, so a database disclosure does not expose a usable credential.
struct CreateAPIKeyCredential: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(APIKeyCredential.schema)
            .id()
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("name", .string, .required)
            .field("key_hash", .string, .required)
            .field("key_prefix", .string, .required)
            .field("expires_at", .datetime)
            .field("last_used_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "key_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(APIKeyCredential.schema).delete()
    }
}
