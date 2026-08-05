import Fluent

/// Creates one user-owned study block per assignment and local calendar day.
/// The unique key makes manual and automatic planning safe to retry.
struct CreateStudySessions: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(StudySession.schema)
            .id()
            .field(
                "task_id",
                .uuid,
                .required,
                .references(Task.schema, "id", onDelete: .cascade)
            )
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("scheduled_date", .string, .required)
            .field("planned_minutes", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "task_id", "user_id", "scheduled_date")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(StudySession.schema).delete()
    }
}
