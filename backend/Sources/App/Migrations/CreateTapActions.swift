import Fluent

/// Creates bearer capabilities and their execution history. Board deletion
/// revokes all related links, while task deletion keeps the audit row intact.
struct CreateTapActions: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TapAction.schema)
            .id()
            .field(
                "board_id",
                .uuid,
                .required,
                .references(Board.schema, "id", onDelete: .cascade)
            )
            .field(
                "target_task_id",
                .uuid,
                .references(Task.schema, "id", onDelete: .setNull)
            )
            .field("name", .string, .required)
            .field("kind", .string, .required)
            .field("configuration", .json, .required)
            .field("token_hash", .string, .required)
            .field("token_prefix", .string, .required)
            .field("is_enabled", .bool, .required, .sql(.default(true)))
            .field("expires_at", .datetime)
            .field("max_uses", .int)
            .field("use_count", .int, .required, .sql(.default(0)))
            .field("cooldown_seconds", .int, .required, .sql(.default(3)))
            .field("last_used_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "token_hash")
            .create()

        try await database.schema(TapExecution.schema)
            .id()
            .field(
                "action_id",
                .uuid,
                .required,
                .references(TapAction.schema, "id", onDelete: .cascade)
            )
            .field(
                "task_id",
                .uuid,
                .references(Task.schema, "id", onDelete: .setNull)
            )
            .field("request_id", .uuid, .required)
            .field("action_name", .string, .required)
            .field("message", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "request_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TapExecution.schema).delete()
        try await database.schema(TapAction.schema).delete()
    }
}
