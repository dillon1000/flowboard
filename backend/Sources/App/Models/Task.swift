import Fluent
import Vapor

enum TaskStatus: String, Codable, CaseIterable, Content, Sendable {
    case backlog
    case inProgress = "in_progress"
    case review
    case done

    var sortOrder: Int {
        switch self {
        case .backlog: 0
        case .inProgress: 1
        case .review: 2
        case .done: 3
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Content, Sendable {
    case low
    case medium
    case high
    case urgent
}

final class Task: Model, @unchecked Sendable {
    static let schema = "tasks"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "title")
    var title: String

    @OptionalField(key: "description")
    var description: String?

    @Enum(key: "status")
    var status: TaskStatus

    @Enum(key: "priority")
    var priority: TaskPriority

    /// Position uses gaps of 1,000 so most moves can be represented without changing
    /// neighboring tasks. The move endpoint normalizes a column after each drop.
    @Field(key: "position")
    var position: Int

    @Field(key: "labels")
    var labels: [String]

    @OptionalField(key: "start_at")
    var startAt: Date?

    @OptionalField(key: "due_at")
    var dueAt: Date?

    @OptionalParent(key: "assignee_id")
    var assignee: User?

    @OptionalParent(key: "created_by_id")
    var creator: User?

    /// Values are keyed by a definition ID from the parent board. A string
    /// representation keeps form handling predictable for all supported field types.
    @OptionalField(key: "properties")
    var properties: [String: String]?

    @Field(key: "is_archived")
    var isArchived: Bool

    @Children(for: \.$task)
    var comments: [TaskComment]

    @Children(for: \.$task)
    var checklistItems: [ChecklistItem]

    @Children(for: \.$task)
    var attachments: [TaskAttachment]

    @Children(for: \.$task)
    var followers: [TaskFollower]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        title: String,
        description: String? = nil,
        status: TaskStatus = .backlog,
        priority: TaskPriority = .medium,
        position: Int,
        labels: [String] = [],
        startAt: Date? = nil,
        dueAt: Date? = nil,
        creatorID: UUID? = nil
    ) {
        self.id = id
        self.$board.id = boardID
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.position = position
        self.labels = labels
        self.startAt = startAt
        self.dueAt = dueAt
        self.$creator.id = creatorID
        self.properties = [:]
        self.isArchived = false
    }
}

struct TaskResponse: Content {
    let id: UUID
    let boardID: UUID
    let boardName: String?
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let position: Int
    let labels: [String]
    let startAt: Date?
    let dueAt: Date?
    let assigneeID: UUID?
    let properties: [String: String]
    let isArchived: Bool
    let createdAt: Date?
    let updatedAt: Date?

    init(task: Task, boardName: String? = nil) throws {
        self.id = try task.requireID()
        self.boardID = task.$board.id
        self.boardName = boardName
        self.title = task.title
        self.description = task.description
        self.status = task.status
        self.priority = task.priority
        self.position = task.position
        self.labels = task.labels
        self.startAt = task.startAt
        self.dueAt = task.dueAt
        self.assigneeID = task.$assignee.id
        self.properties = task.properties ?? [:]
        self.isArchived = task.isArchived
        self.createdAt = task.createdAt
        self.updatedAt = task.updatedAt
    }
}

struct CreateTaskRequest: Content, Validatable {
    let boardID: UUID
    let title: String
    let description: String?
    let status: TaskStatus?
    let priority: TaskPriority?
    let labels: [String]?
    let startAt: Date?
    let dueAt: Date?
    let assigneeID: UUID?
    let properties: [String: String]?

    init(
        boardID: UUID,
        title: String,
        description: String?,
        status: TaskStatus?,
        priority: TaskPriority?,
        labels: [String]?,
        startAt: Date? = nil,
        dueAt: Date?,
        assigneeID: UUID? = nil,
        properties: [String: String]? = nil
    ) {
        self.boardID = boardID
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.labels = labels
        self.startAt = startAt
        self.dueAt = dueAt
        self.assigneeID = assigneeID
        self.properties = properties
    }

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: .count(1...120))
        validations.add("description", as: String.self, is: .count(...2_000), required: false)
        validations.add("labels", as: [String].self, is: .count(...6), required: false)
    }
}

struct UpdateTaskRequest: Content, Validatable {
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let labels: [String]
    let startAt: Date?
    let dueAt: Date?
    let assigneeID: UUID?
    let properties: [String: String]?

    init(
        title: String,
        description: String?,
        status: TaskStatus,
        priority: TaskPriority,
        labels: [String],
        startAt: Date? = nil,
        dueAt: Date?,
        assigneeID: UUID? = nil,
        properties: [String: String]? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.labels = labels
        self.startAt = startAt
        self.dueAt = dueAt
        self.assigneeID = assigneeID
        self.properties = properties
    }

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: .count(1...120))
        validations.add("description", as: String.self, is: .count(...2_000), required: false)
        validations.add("labels", as: [String].self, is: .count(...6))
    }
}

struct MoveTaskRequest: Content, Validatable {
    let status: TaskStatus
    let targetIndex: Int

    static func validations(_ validations: inout Validations) {
        validations.add("targetIndex", as: Int.self, is: .range(0...10_000))
    }
}
