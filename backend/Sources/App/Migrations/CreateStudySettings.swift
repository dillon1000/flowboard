import Fluent

/// Stores the durable inputs used by estimation, onboarding, and allocation.
/// JSON fields keep the small per-user collections atomic and easy to replace.
struct CreateStudySettings: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(StudySettings.schema)
            .id()
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("weekday_capacity_minutes", .json, .required)
            .field("blocked_dates", .json, .required)
            .field("recurring_commitments", .json, .required)
            .field("calendar_conflicts", .json, .required)
            .field("estimate_presets", .json, .required)
            .field("time_zone_confirmed", .bool, .required, .sql(.default(false)))
            .field("availability_configured", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(StudySettings.schema).delete()
    }
}
