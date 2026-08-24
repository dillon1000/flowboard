import Fluent
import Foundation
import Vapor

enum BoardViewType: String, Codable, CaseIterable, Content, Sendable {
    case board
    case table
    case calendar
    case gantt
    case gallery
}

struct BoardViewFilter: Codable, Sendable {
    let field: String
    let comparison: String
    let value: String
}

struct BoardViewSort: Codable, Sendable {
    let field: String
    let direction: String
}

struct BoardViewConfiguration: Codable, Sendable {
    let groupBy: String?
    let filters: [BoardViewFilter]
    let sorts: [BoardViewSort]
}

final class BoardView: Model, @unchecked Sendable {
    static let schema = "board_views"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "name")
    var name: String

    @Field(key: "slug")
    var slug: String

    @Enum(key: "type")
    var type: BoardViewType

    @Field(key: "position")
    var position: Int

    /// Configuration stores grouping, filters, and sorting together so a saved
    /// view can be restored with one query and changed without a schema migration.
    @OptionalField(key: "configuration")
    var configuration: BoardViewConfiguration?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        name: String,
        slug: String? = nil,
        type: BoardViewType,
        position: Int,
        configuration: BoardViewConfiguration? = nil
    ) {
        self.id = id
        self.$board.id = boardID
        self.name = name
        self.slug = slug ?? Self.slugify(name)
        self.type = type
        self.position = position
        self.configuration = configuration
    }

    static func slugify(_ value: String) -> String {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "view" : normalized).prefix(48))
    }

    static func uniqueSlug(
        for name: String,
        boardID: UUID,
        on database: any Database
    ) async throws -> String {
        let base = slugify(name)
        let existing = try await BoardView.query(on: database)
            .filter(\.$board.$id == boardID)
            .all()
        let slugs = Set(existing.map { $0.slug.lowercased() })
        guard slugs.contains(base) else { return base }
        for suffix in 2...10_000 {
            let candidate = "\(String(base.prefix(43)))-\(suffix)"
            if !slugs.contains(candidate) { return candidate }
        }
        throw Abort(.internalServerError, reason: "A view URL could not be generated.")
    }
}
