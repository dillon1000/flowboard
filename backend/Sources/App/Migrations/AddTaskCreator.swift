import Fluent

/// Stores the user who created each task. Earlier tasks use the board owner
/// because the application did not record a separate creator at that time.
struct AddTaskCreator: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .field(
                "created_by_id",
                .uuid,
                .references(User.schema, "id", onDelete: .setNull)
            )
            .update()

        let boards = try await Board.query(on: database).all()
        for board in boards {
            guard
                let boardID = board.id,
                let ownerID = board.$owner.id
            else {
                continue
            }
            try await Task.query(on: database)
                .filter(\.$board.$id == boardID)
                .set(["created_by_id": .bind(ownerID)])
                .update()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Task.schema)
            .deleteField("created_by_id")
            .update()
    }
}
