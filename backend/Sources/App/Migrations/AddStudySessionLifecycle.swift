import Fluent

/// Adds execution truth to planned study blocks. Existing rows remain planned,
/// so a later repair can distinguish missed work from completed work.
struct AddStudySessionLifecycle: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(StudySession.schema)
            .field("state", .string, .required, .sql(.default("planned")))
            .update()
        try await database.schema(StudySession.schema)
            .field("actual_minutes", .int)
            .update()
        try await database.schema(StudySession.schema)
            .field("completed_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(StudySession.schema)
            .deleteField("completed_at")
            .update()
        try await database.schema(StudySession.schema)
            .deleteField("actual_minutes")
            .update()
        try await database.schema(StudySession.schema)
            .deleteField("state")
            .update()
    }
}
