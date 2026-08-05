import Fluent
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
        type: BoardViewType,
        position: Int,
        configuration: BoardViewConfiguration? = nil
    ) {
        self.id = id
        self.$board.id = boardID
        self.name = name
        self.type = type
        self.position = position
        self.configuration = configuration
    }
}
