import Fluent

/// Adds the standard four views to boards created before saved views existed.
/// The existence check makes the migration safe for mixed-version databases.
struct BackfillBoardViews: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let boards = try await Board.query(on: database).all()
        for board in boards {
            let boardID = try board.requireID()
            let count = try await BoardView.query(on: database)
                .filter(\.$board.$id == boardID)
                .count()
            guard count == 0 else { continue }

            let views: [(String, BoardViewType)] = [
                ("Board", .board),
                ("Table", .table),
                ("Calendar", .calendar),
                ("Gallery", .gallery),
            ]
            for (position, view) in views.enumerated() {
                try await BoardView(
                    boardID: boardID,
                    name: view.0,
                    type: view.1,
                    position: position
                ).create(on: database)
            }
        }
    }

    func revert(on database: any Database) async throws {}
}
