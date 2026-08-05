import Fluent

/// Adds optional assessment scores without changing ungraded assignments.
struct AddTaskGradeFields: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .field("grade_earned", .double)
            .update()
        try await database.schema(Task.schema)
            .field("grade_possible", .double)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .deleteField("grade_earned")
            .update()
        try await database.schema(Task.schema)
            .deleteField("grade_possible")
            .update()
    }
}
