import Vapor

struct BoardMemberResponse: Content {
    let id: UUID?
    let userID: UUID
    let name: String
    let email: String
    let role: BoardMemberRole
    let isOwner: Bool
    let createdAt: Date?

    init(member: BoardMember?, user: User, role: BoardMemberRole, isOwner: Bool) throws {
        self.id = member?.id
        self.userID = try user.requireID()
        self.name = user.name
        self.email = user.email
        self.role = role
        self.isOwner = isOwner
        self.createdAt = member?.createdAt ?? user.createdAt
    }
}

struct BoardViewResponse: Content {
    let id: UUID
    let boardID: UUID
    let name: String
    let type: BoardViewType
    let position: Int
    let configuration: BoardViewConfiguration?
    let createdAt: Date?
    let updatedAt: Date?

    init(view: BoardView) throws {
        self.id = try view.requireID()
        self.boardID = view.$board.id
        self.name = view.name
        self.type = view.type
        self.position = view.position
        self.configuration = view.configuration
        self.createdAt = view.createdAt
        self.updatedAt = view.updatedAt
    }
}

struct TaskTemplateResponse: Content {
    let id: UUID
    let boardID: UUID
    let name: String
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let labels: [String]
    let isDefault: Bool
    let createdAt: Date?

    init(template: TaskTemplate) throws {
        self.id = try template.requireID()
        self.boardID = template.$board.id
        self.name = template.name
        self.title = template.title
        self.description = template.description
        self.status = template.status
        self.priority = template.priority
        self.labels = template.labels
        self.isDefault = template.isDefault
        self.createdAt = template.createdAt
    }
}

struct CreateBoardMemberRequest: Content, Validatable {
    let email: String
    let role: BoardMemberRole

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
    }
}

struct UpdateBoardMemberRequest: Content {
    let role: BoardMemberRole
}

struct CreateBoardViewRequest: Content, Validatable {
    let name: String
    let type: BoardViewType
    let configuration: BoardViewConfiguration?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(1...80))
    }
}

struct PatchBoardViewRequest: Content {
    @PatchField var name: PatchField<String>.State
    @PatchField var type: PatchField<BoardViewType>.State
    @PatchField var configuration: PatchField<BoardViewConfiguration>.State
}

struct CreateTaskTemplateRequest: Content, Validatable {
    let name: String
    let title: String
    let description: String?
    let status: TaskStatus?
    let priority: TaskPriority?
    let labels: [String]?
    let isDefault: Bool?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(1...80))
        validations.add("title", as: String.self, is: .count(1...120))
        validations.add("description", as: String.self, is: .count(...5_000), required: false)
        validations.add("labels", as: [String].self, is: .count(...6), required: false)
    }
}

struct PatchTaskTemplateRequest: Content {
    @PatchField var name: PatchField<String>.State
    @PatchField var title: PatchField<String>.State
    @PatchField var description: PatchField<String>.State
    @PatchField var status: PatchField<TaskStatus>.State
    @PatchField var priority: PatchField<TaskPriority>.State
    @PatchField var labels: PatchField<[String]>.State
    @PatchField var isDefault: PatchField<Bool>.State
}
