import Fluent

/// Adds user-written Tap page copy to actions and execution records. Existing
/// actions stay valid and use the default completion copy until an owner edits them.
struct AddTapActionDisplayDescription: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TapAction.schema)
            .field("display_description", .string)
            .update()
        try await database.schema(TapExecution.schema)
            .field("action_description", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TapExecution.schema)
            .deleteField("action_description")
            .update()
        try await database.schema(TapAction.schema)
            .deleteField("display_description")
            .update()
    }
}
