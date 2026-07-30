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

    @Children(for: \.$board)
    var tasks: [Task]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
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
            .map(TaskResponse.init)
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}

struct CreateBoardRequest: Content, Validatable {
    let name: String
    let slug: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add(
            "slug",
            as: String.self,
            is: .count(2...48) && .characterSet(.alphanumerics + CharacterSet(charactersIn: "-"))
        )
    }
}
