import Fluent
import Foundation

private final class BoardViewSlugBackfill: Model, @unchecked Sendable {
    static let schema = BoardView.schema

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "name")
    var name: String

    @OptionalField(key: "slug")
    var slug: String?

    init() {}
}

/// Adds stable, readable URL segments for saved views. Slugs are unique within a
/// board, so two views with the same name become `planning` and `planning-2`.
struct AddBoardViewSlug: AsyncMigration {
    private let indexName = "uq_board_views_board_id_slug"

    func prepare(on database: any Database) async throws {
        try await database.schema(BoardView.schema)
            .field("slug", .string)
            .update()

        let views = try await BoardViewSlugBackfill.query(on: database).all()
        var assignedByBoard: [UUID: Set<String>] = [:]
        for view in views {
            let boardID = view.$board.id
            let base = BoardView.slugify(view.name)
            var candidate = base
            var suffix = 2
            while assignedByBoard[boardID, default: []].contains(candidate) {
                candidate = "\(String(base.prefix(43)))-\(suffix)"
                suffix += 1
            }
            assignedByBoard[boardID, default: []].insert(candidate)
            view.slug = candidate
            try await view.update(on: database)
        }

        let index = BoardViewSlugBackfill.query(on: database)
        index.query.action = .custom(
            "CREATE UNIQUE INDEX \"\(indexName)\" ON \"\(BoardView.schema)\" (\"board_id\", \"slug\" COLLATE NOCASE)"
        )
        try await index.run().get()
    }

    func revert(on database: any Database) async throws {
        let index = BoardViewSlugBackfill.query(on: database)
        index.query.action = .custom("DROP INDEX IF EXISTS \"\(indexName)\"")
        try await index.run().get()
        try await database.schema(BoardView.schema)
            .deleteField("slug")
            .update()
    }
}
