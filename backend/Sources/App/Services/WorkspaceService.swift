import Fluent
import Foundation

enum WorkspaceService {
    /// Creates a board and its four standard views in the caller's transaction.
    /// A view failure rolls back the board so navigation never opens an empty shell.
    static func createBoard(
        name: String,
        slug: String,
        description: String? = nil,
        ownerID: UUID,
        on database: any Database
    ) async throws -> Board {
        let board = Board(
            name: name,
            slug: slug,
            description: description,
            ownerID: ownerID
        )
        try await board.create(on: database)
        let boardID = try board.requireID()

        let views: [(String, BoardViewType)] = [
            ("Board", .board),
            ("Table", .table),
            ("Calendar", .calendar),
            ("Gallery", .gallery),
        ]
        for (index, view) in views.enumerated() {
            try await BoardView(
                boardID: boardID,
                name: view.0,
                type: view.1,
                position: index
            ).create(on: database)
        }
        return board
    }
}
