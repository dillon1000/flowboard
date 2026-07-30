import Fluent
import Vapor

final class ChecklistItem: Model, @unchecked Sendable {
    static let schema = "checklist_items"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: Task

    @Field(key: "title")
    var title: String

    @Field(key: "is_completed")
    var isCompleted: Bool

    @Field(key: "position")
    var position: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        taskID: UUID,
        title: String,
        isCompleted: Bool = false,
        position: Int
    ) {
        self.id = id
        self.$task.id = taskID
        self.title = title
        self.isCompleted = isCompleted
        self.position = position
    }
}
