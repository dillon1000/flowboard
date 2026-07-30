import Fluent

struct CreateTaskFollowers: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TaskFollower.schema)
            .id()
            .field("task_id", .uuid, .required, .references(Task.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "task_id", "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TaskFollower.schema).delete()
    }
}
