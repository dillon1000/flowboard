import Fluent
import Vapor

final class Board: Model, @unchecked Sendable {
    static let schema = "boards"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "slug")
    var slug: String

    @OptionalField(key: "description")
    var description: String?

    @Field(key: "is_archived")
    var isArchived: Bool

    /// Board-level definitions let each board add typed fields without changing
    /// the SQL schema for every new property that a user creates.
    @OptionalField(key: "property_definitions")
    var propertyDefinitions: [BoardPropertyDefinition]?

    @OptionalParent(key: "owner_id")
    var owner: User?

    @Children(for: \.$board)
    var tasks: [Task]

    @Children(for: \.$board)
    var views: [BoardView]

    @Children(for: \.$board)
    var members: [BoardMember]

    @Children(for: \.$board)
    var templates: [TaskTemplate]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        slug: String,
        description: String? = nil,
        ownerID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.isArchived = false
        self.propertyDefinitions = []
        self.$owner.id = ownerID
    }
}

enum BoardPropertyType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case select
    case multiSelect = "multi_select"
    case date
    case checkbox
    case url
    case email
    case person
}

struct BoardPropertyOption: Codable, Sendable {
    let id: String
    let name: String
    let color: String
}

struct BoardPropertyDefinition: Codable, Sendable {
    let id: String
    let name: String
    let type: BoardPropertyType
    let options: [BoardPropertyOption]
}

struct BoardResponse: Content {
    let id: UUID
    let name: String
    let slug: String
    let tasks: [TaskResponse]
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task] = []) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.tasks = try tasks
            .sorted { ($0.status.sortOrder, $0.position) < ($1.status.sortOrder, $1.position) }
            .map { try TaskResponse(task: $0) }
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}

struct CreateBoardRequest: Content, Validatable {
    let name: String
    let slug: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add(
            "slug",
            as: String?.self,
            is: .nil || (.count(2...48) && .characterSet(.alphanumerics + CharacterSet(charactersIn: "-")))
        )
    }
}

struct UpdateBoardRequest: Content, Validatable {
    let name: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
    }
}

struct BoardSummaryResponse: Content {
    let id: UUID
    let name: String
    let slug: String
    let taskCount: Int
    let completedCount: Int
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task]) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.taskCount = tasks.count
        self.completedCount = tasks.filter { $0.status == .done }.count
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}
