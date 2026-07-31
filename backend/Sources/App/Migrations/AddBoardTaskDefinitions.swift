import Fluent

/// Adds board-owned task choices without rewriting existing task rows. A null
/// value selects the standard definitions in the model, so older boards keep
/// their current workflow until an administrator adds a choice.
struct AddBoardTaskDefinitions: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .field("status_definitions", .json)
            .update()
        try await database.schema(Board.schema)
            .field("severity_definitions", .json)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .deleteField("status_definitions")
            .update()
        try await database.schema(Board.schema)
            .deleteField("severity_definitions")
            .update()
    }
}
