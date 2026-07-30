import Fluent
import Vapor

final class TaskFollower: Model, @unchecked Sendable {
    static let schema = "task_followers"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: Task

    @Parent(key: "user_id")
    var user: User

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, taskID: UUID, userID: UUID) {
        self.id = id
        self.$task.id = taskID
        self.$user.id = userID
    }
}
