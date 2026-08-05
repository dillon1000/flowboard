import Fluent

/// Adds opt-in planning email controls. Seven is the default local delivery
/// hour, but both message types stay disabled until the user enables them.
struct AddPlanningNotificationPreferences: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("daily_brief_enabled", .bool, .required, .sql(.default(false)))
            .update()
        try await database.schema(User.schema)
            .field("weekly_planning_prompt_enabled", .bool, .required, .sql(.default(false)))
            .update()
        try await database.schema(User.schema)
            .field("planning_email_hour", .int, .required, .sql(.default(7)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("daily_brief_enabled")
            .update()
        try await database.schema(User.schema)
            .deleteField("weekly_planning_prompt_enabled")
            .update()
        try await database.schema(User.schema)
            .deleteField("planning_email_hour")
            .update()
    }
}
