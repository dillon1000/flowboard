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

    /// These ordered JSON arrays define the choices shown for every task on this
    /// board. A nil value means that the board uses the standard choices.
    @OptionalField(key: "status_definitions")
    var statusDefinitions: [BoardTaskOption]?

    @OptionalField(key: "severity_definitions")
    var severityDefinitions: [BoardTaskOption]?

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
        self.statusDefinitions = BoardTaskOption.defaultStatuses
        self.severityDefinitions = BoardTaskOption.defaultSeverities
        self.$owner.id = ownerID
    }

    var taskStatuses: [BoardTaskOption] {
        statusDefinitions ?? BoardTaskOption.defaultStatuses
    }

    var taskSeverities: [BoardTaskOption] {
        severityDefinitions ?? BoardTaskOption.defaultSeverities
    }

    func statusOption(for status: TaskStatus) -> BoardTaskOption {
        taskStatuses.first { $0.id == status.rawValue }
            ?? BoardTaskOption.fallback(id: status.rawValue)
    }

    func severityOption(for priority: TaskPriority) -> BoardTaskOption {
        taskSeverities.first { $0.id == priority.rawValue }
            ?? BoardTaskOption.fallback(id: priority.rawValue)
    }

    func accepts(status: TaskStatus) -> Bool {
        taskStatuses.contains { $0.id == status.rawValue }
    }

    func accepts(priority: TaskPriority) -> Bool {
        taskSeverities.contains { $0.id == priority.rawValue }
    }

    func isCompleted(_ status: TaskStatus) -> Bool {
        statusOption(for: status).isCompleted
    }
}

enum BoardTaskOptionColor: String, Codable, CaseIterable, Sendable {
    case gray
    case blue
    case purple
    case green
    case amber
    case orange
    case red
}

/// One board-owned status or severity choice. IDs are immutable task values,
/// while names and colors control how those values appear in the interface.
struct BoardTaskOption: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let color: BoardTaskOptionColor
    let isCompleted: Bool

    static let defaultStatuses = [
        Self(id: "backlog", name: "Backlog", color: .gray, isCompleted: false),
        Self(id: "in_progress", name: "In progress", color: .blue, isCompleted: false),
        Self(id: "review", name: "Review", color: .purple, isCompleted: false),
        Self(id: "done", name: "Done", color: .green, isCompleted: true),
    ]

    static let defaultSeverities = [
        Self(id: "low", name: "Low", color: .gray, isCompleted: false),
        Self(id: "medium", name: "Medium", color: .amber, isCompleted: false),
        Self(id: "high", name: "High", color: .orange, isCompleted: false),
        Self(id: "urgent", name: "Urgent", color: .red, isCompleted: false),
    ]

    static func fallback(id: String) -> Self {
        Self(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            color: .gray,
            isCompleted: id == TaskStatus.done.rawValue
        )
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
    let description: String?
    let isArchived: Bool
    let propertyDefinitions: [BoardPropertyDefinition]
    let statusDefinitions: [BoardTaskOption]
    let severityDefinitions: [BoardTaskOption]
    let tasks: [TaskResponse]
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task] = []) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.description = board.description
        self.isArchived = board.isArchived
        self.propertyDefinitions = board.propertyDefinitions ?? []
        self.statusDefinitions = board.taskStatuses
        self.severityDefinitions = board.taskSeverities
        self.tasks = try tasks
            .sorted { left, right in
                let leftIndex = board.taskStatuses.firstIndex { option in
                    option.id == left.statusValue
                }
                    ?? board.taskStatuses.count
                let rightIndex = board.taskStatuses.firstIndex { option in
                    option.id == right.statusValue
                }
                    ?? board.taskStatuses.count
                return (leftIndex, left.position) < (rightIndex, right.position)
            }
            .map { try TaskResponse(task: $0) }
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}

struct CreateBoardRequest: Content, Validatable {
    let name: String
    let slug: String?
    let description: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add(
            "slug",
            as: String.self,
            is: .count(2...48) && .characterSet(.alphanumerics + CharacterSet(charactersIn: "-")),
            required: false
        )
        validations.add("description", as: String.self, is: .count(...500), required: false)
    }
}

struct UpdateBoardRequest: Content, Validatable {
    let name: String
    let description: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add("description", as: String.self, is: .count(...500), required: false)
    }
}

struct BoardSummaryResponse: Content {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let isArchived: Bool
    let taskCount: Int
    let completedCount: Int
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task]) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.description = board.description
        self.isArchived = board.isArchived
        self.taskCount = tasks.count
        self.completedCount = tasks.filter { board.isCompleted($0.status) }.count
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}
