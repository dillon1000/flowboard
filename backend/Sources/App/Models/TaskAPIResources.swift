import Vapor

struct TaskCommentResponse: Content {
    let id: UUID
    let taskID: UUID
    let authorID: UUID
    let authorName: String
    let body: String
    let createdAt: Date?
    let updatedAt: Date?

    init(comment: TaskComment, authorName: String) throws {
        self.id = try comment.requireID()
        self.taskID = comment.$task.id
        self.authorID = comment.$author.id
        self.authorName = authorName
        self.body = comment.body
        self.createdAt = comment.createdAt
        self.updatedAt = comment.updatedAt
    }
}

struct TaskChecklistItemResponse: Content {
    let id: UUID
    let taskID: UUID
    let title: String
    let isCompleted: Bool
    let position: Int
    let createdAt: Date?

    init(item: ChecklistItem) throws {
        self.id = try item.requireID()
        self.taskID = item.$task.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.position = item.position
        self.createdAt = item.createdAt
    }
}

struct TaskFollowerResponse: Content {
    let id: UUID
    let taskID: UUID
    let userID: UUID
    let userName: String
    let profilePictureURL: String?
    let createdAt: Date?

    init(follower: TaskFollower, user: User) throws {
        self.id = try follower.requireID()
        self.taskID = follower.$task.id
        self.userID = follower.$user.id
        self.userName = user.name
        self.profilePictureURL = user.profilePictureURL
        self.createdAt = follower.createdAt
    }
}

struct CreateTaskCommentRequest: Content, Validatable {
    let body: String

    static func validations(_ validations: inout Validations) {
        validations.add("body", as: String.self, is: .count(1...4_000))
    }
}

struct CreateChecklistItemRequest: Content, Validatable {
    let title: String

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: .count(1...200))
    }
}

struct UpdateChecklistItemRequest: Content {
    let title: String?
    let isCompleted: Bool?
}

struct MoveChecklistItemRequest: Content, Validatable {
    let targetIndex: Int

    static func validations(_ validations: inout Validations) {
        validations.add("targetIndex", as: Int.self, is: .range(0...10_000))
    }
}
