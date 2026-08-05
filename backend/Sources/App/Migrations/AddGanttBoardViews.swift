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
            let views = try await BoardView.query(on: database)
                .filter(\.$board.$id == boardID)
                .sort(\.$position, .ascending)
                .all()
            guard !views.contains(where: { $0.type == .gantt }) else { continue }

            // Existing boards place Gallery fourth. Insert Gantt before it so
            // migrated and newly created boards keep the same tab order.
            let position = views.first(where: { $0.type == .gallery })?.position
                ?? ((views.map(\.position).max() ?? -1) + 1)
            for view in views where view.position >= position {
                view.position += 1
                try await view.update(on: database)
            }
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
