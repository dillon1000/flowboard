import Fluent

/// Adds honest planning data to existing tasks. Both fields remain optional so
/// earlier tasks stay valid until a student chooses to add an estimate or time.
struct AddStudyTaskPlanningFields: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .field("due_time", .string)
            .update()
        try await database.schema(Task.schema)
            .field("estimated_minutes", .int)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .deleteField("due_time")
            .update()
        try await database.schema(Task.schema)
            .deleteField("estimated_minutes")
            .update()
    }
}
