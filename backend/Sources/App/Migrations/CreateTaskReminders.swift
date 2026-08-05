import Fluent

struct CreateTaskReminders: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TaskReminder.schema)
            .id()
            .field("task_id", .uuid, .required, .references(Task.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("remind_at", .datetime, .required)
            .field("time_zone", .string, .required)
            .field("queued_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "task_id", "user_id", "remind_at")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TaskReminder.schema).delete()
    }
}
