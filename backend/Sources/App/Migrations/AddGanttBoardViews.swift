import Fluent

/// Extends saved layouts with Gantt and gives each existing board one timeline.
/// The type update changes native enums where the database supports them. The
/// existence check keeps imported or manually created Gantt views unchanged.
struct AddGanttBoardViews: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let viewType = try await database.enum("board_view_type")
            .case("gantt")
            .update()
        try await database.schema(BoardView.schema)
            .updateField("type", viewType)
            .update()

        let boards = try await Board.query(on: database).all()
        for board in boards {
            let boardID = try board.requireID()
            let existing = try await BoardView.query(on: database)
                .filter(\.$board.$id == boardID)
                .filter(\.$type == .gantt)
                .first()
            guard existing == nil else { continue }

            let position = try await BoardView.query(on: database)
                .filter(\.$board.$id == boardID)
                .count()
            try await BoardView(
                boardID: boardID,
                name: "Gantt",
                type: .gantt,
                position: position
            ).create(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        try await BoardView.query(on: database)
            .filter(\.$type == .gantt)
            .delete()
        let viewType = try await database.enum("board_view_type")
            .deleteCase("gantt")
            .update()
        try await database.schema(BoardView.schema)
            .updateField("type", viewType)
            .update()
    }
}
