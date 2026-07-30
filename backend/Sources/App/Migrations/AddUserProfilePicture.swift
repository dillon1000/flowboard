import Fluent

/// Adds the optional provider-managed image URL without changing password users.
/// OAuth callbacks refresh this value when the provider picture changes.
struct AddUserProfilePicture: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("profile_picture_url", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("profile_picture_url")
            .update()
    }
}
