import Fluent

/// Adds flexible board and task fields without replacing existing rows. Optional
/// JSON columns preserve compatibility with databases created by earlier builds.
struct ExpandWorkspace: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .field("description", .string)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .field("property_definitions", .json)
            .update()

        try await database.schema(Task.schema)
            .field("start_at", .datetime)
            .field(
                "assignee_id",
                .uuid,
                .references(User.schema, "id", onDelete: .setNull)
            )
            .field("properties", .json)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .deleteField("start_at")
            .deleteField("assignee_id")
            .deleteField("properties")
            .deleteField("is_archived")
            .update()
        try await database.schema(Board.schema)
            .deleteField("description")
            .deleteField("is_archived")
            .deleteField("property_definitions")
            .update()
    }
}
