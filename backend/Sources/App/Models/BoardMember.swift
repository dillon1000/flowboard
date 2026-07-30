import Fluent
import Vapor

enum BoardMemberRole: String, Codable, CaseIterable, Content, Sendable {
    case viewer
    case commenter
    case editor
    case admin

    var canEdit: Bool {
        self == .editor || self == .admin
    }

    var canComment: Bool {
        self != .viewer
    }
}

final class BoardMember: Model, @unchecked Sendable {
    static let schema = "board_members"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Parent(key: "user_id")
    var user: User

    @Enum(key: "role")
    var role: BoardMemberRole

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, boardID: UUID, userID: UUID, role: BoardMemberRole) {
        self.id = id
        self.$board.id = boardID
        self.$user.id = userID
        self.role = role
    }
}
