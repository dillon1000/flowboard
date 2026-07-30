import Fluent

struct CreateTask: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let status = try await database.enum("task_status")
            .case("backlog")
            .case("in_progress")
            .case("review")
            .case("done")
            .create()
        let priority = try await database.enum("task_priority")
            .case("low")
            .case("medium")
            .case("high")
            .case("urgent")
            .create()

        try await database.schema(Task.schema)
            .id()
            .field("board_id", .uuid, .required, .references(Board.schema, "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("description", .string)
            .field("status", status, .required)
            .field("priority", priority, .required)
            .field("position", .int, .required)
            .field("labels", .json, .required)
            .field("due_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema).delete()
        try await database.enum("task_priority").delete()
        try await database.enum("task_status").delete()
    }
}
