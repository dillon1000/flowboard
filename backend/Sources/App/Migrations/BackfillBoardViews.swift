import Fluent
import Foundation

/// Keeps pre-slug migrations independent from the current BoardView fields.
final class LegacyBoardView: Model, @unchecked Sendable {
    static let schema = BoardView.schema

    @ID(key: .id) var id: UUID?
    @Parent(key: "board_id") var board: Board
    @Field(key: "name") var name: String
    @Enum(key: "type") var type: BoardViewType
    @Field(key: "position") var position: Int
    @OptionalField(key: "configuration") var configuration: BoardViewConfiguration?

    init() {}

    init(boardID: UUID, name: String, type: BoardViewType, position: Int) {
        self.$board.id = boardID
        self.name = name
        self.type = type
        self.position = position
    }
}

/// Adds the standard four views to boards created before saved views existed.
/// The existence check makes the migration safe for mixed-version databases.
struct BackfillBoardViews: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let boards = try await Board.query(on: database).all()
        for board in boards {
            let boardID = try board.requireID()
            let count = try await LegacyBoardView.query(on: database)
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
                try await LegacyBoardView(
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
