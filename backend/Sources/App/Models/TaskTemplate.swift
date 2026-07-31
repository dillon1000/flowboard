import Fluent
import Vapor

final class TaskTemplate: Model, @unchecked Sendable {
    static let schema = "task_templates"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "name")
    var name: String

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

    @Field(key: "labels")
    var labels: [String]

    @Field(key: "is_default")
    var isDefault: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        name: String,
        title: String,
        description: String? = nil,
        status: TaskStatus = .backlog,
        priority: TaskPriority = .medium,
        labels: [String] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.$board.id = boardID
        self.name = name
        self.title = title
        self.description = description
        self.statusValue = status.rawValue
        self.priorityValue = priority.rawValue
        self.labels = labels
        self.isDefault = isDefault
    }
}
