import Fluent

struct CreateBoard: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Board.schema)
            .id()
            .field("name", .string, .required)
            .field("slug", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "slug")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Board.schema).delete()
    }
}
