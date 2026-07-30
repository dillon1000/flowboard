import Fluent

/// Persists provider subjects separately from email addresses because providers
/// can change a user's email while their stable subject remains the same.
struct CreateOAuthAccount: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(OAuthAccount.schema)
            .id()
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("provider_id", .string, .required)
            .field("provider_user_id", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "provider_id", "provider_user_id")
            .unique(on: "user_id", "provider_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(OAuthAccount.schema).delete()
    }
}
