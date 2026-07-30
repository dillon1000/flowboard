import Fluent

/// Adds ownership as an optional field so an existing local database can migrate
/// without deleting its earlier sample board. All new boards always set an owner.
struct AddBoardOwner: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .field(
                "owner_id",
                .uuid,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .deleteField("owner_id")
            .update()
    }
}
