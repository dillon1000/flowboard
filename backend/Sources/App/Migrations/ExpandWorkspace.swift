import Fluent

/// Adds flexible board and task fields without replacing existing rows. Optional
/// JSON columns preserve compatibility with databases created by earlier builds.
struct ExpandWorkspace: AsyncMigration {
    func prepare(on database: any Database) async throws {
        // SQLite accepts one added column per ALTER TABLE statement.
        try await database.schema(Board.schema)
            .field("description", .string)
            .update()
        try await database.schema(Board.schema)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .update()
        try await database.schema(Board.schema)
            .field("property_definitions", .json)
            .update()

        try await database.schema(Task.schema)
            .field("start_at", .datetime)
            .update()
        try await database.schema(Task.schema)
            .field(
                "assignee_id",
                .uuid,
                .references(User.schema, "id", onDelete: .setNull)
            )
            .update()
        try await database.schema(Task.schema)
            .field("properties", .json)
            .update()
        try await database.schema(Task.schema)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .deleteField("start_at")
            .update()
        try await database.schema(Task.schema)
            .deleteField("assignee_id")
            .update()
        try await database.schema(Task.schema)
            .deleteField("properties")
            .update()
        try await database.schema(Task.schema)
            .deleteField("is_archived")
            .update()
        try await database.schema(Board.schema)
            .deleteField("description")
            .update()
        try await database.schema(Board.schema)
            .deleteField("is_archived")
            .update()
        try await database.schema(Board.schema)
            .deleteField("property_definitions")
            .update()
    }
}
