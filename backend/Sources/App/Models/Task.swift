import Fluent
import Vapor

/// A string-backed value keeps the public task contract stable while each board
/// can define additional values. Controllers validate the value against its board.
struct TaskStatus: Codable, Content, Hashable, Sendable {
    let rawValue: String

    static let backlog = Self(rawValue: "backlog")
    static let inProgress = Self(rawValue: "in_progress")
    static let review = Self(rawValue: "review")
    static let done = Self(rawValue: "done")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The database and API continue to call this field `priority` for compatibility.
/// The product presents it as severity and boards can add their own values.
struct TaskPriority: Codable, Content, Hashable, Sendable {
    let rawValue: String

    static let low = Self(rawValue: "low")
    static let medium = Self(rawValue: "medium")
    static let high = Self(rawValue: "high")
    static let urgent = Self(rawValue: "urgent")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

final class Task: Model, @unchecked Sendable {
    static let schema = "tasks"

    /// Six base-36 characters give 2.1 billion case-insensitive keys. The unique
    /// database index is the final guard against a random collision.
    private static let publicIDCharacters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let publicIDLength = 6

    @ID(key: .id)
    var id: UUID?

    @Field(key: "public_id")
    var publicID: String

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "title")
    var title: String

    @OptionalField(key: "description")
    var description: String?

    @Field(key: "status")
    var statusValue: String

    @Field(key: "priority")
    var priorityValue: String

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusValue) }
        set { statusValue = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityValue) }
        set { priorityValue = newValue.rawValue }
    }

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
        publicID: String? = nil,
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
        self.publicID = publicID ?? Self.randomPublicID()
        self.$board.id = boardID
        self.title = title
        self.description = description
        self.statusValue = status.rawValue
        self.priorityValue = priority.rawValue
        self.position = position
        self.labels = labels
        self.startAt = startAt
        self.dueAt = dueAt
        self.$creator.id = creatorID
        self.properties = [:]
        self.isArchived = false
    }

    /// Returns a URL-safe random key. Call uniquePublicID before normal task
    /// creation so a collision is retried before the database insert.
    static func randomPublicID() -> String {
        String((0..<publicIDLength).map { _ in publicIDCharacters.randomElement()! })
    }

    /// Finds an unused key for a new task. The unique index still protects two
    /// concurrent requests that happen to select the same candidate.
    static func uniquePublicID(on database: any Database) async throws -> String {
        for _ in 0..<20 {
            let candidate = randomPublicID()
            let exists = try await Task.query(on: database)
                .filter(\.$publicID == candidate)
                .first() != nil
            if !exists {
                return candidate
            }
        }
        throw Abort(.internalServerError, reason: "A public task ID could not be generated.")
    }

    /// Extracts the case-insensitive key from either a full title slug or the key
    /// alone. Invalid keys stop before a database query is made.
    static func publicID(fromRouteSegment segment: String) -> String? {
        guard let suffix = segment.split(separator: "-").last else {
            return nil
        }
        let candidate = suffix.lowercased()
        guard
            candidate.count == publicIDLength,
            candidate.allSatisfy({ publicIDCharacters.contains($0) })
        else {
            return nil
        }
        return candidate
    }

    /// Builds the canonical browser path from the current title and stable key.
    /// Route lookup uses only the final key, so an older title slug keeps working.
    var browserPath: String {
        let normalizedTitle = title
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let titleSlug = String((normalizedTitle.isEmpty ? "task" : normalizedTitle).prefix(72))
        return "/app/tasks/\(titleSlug)-\(publicID.lowercased())"
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
