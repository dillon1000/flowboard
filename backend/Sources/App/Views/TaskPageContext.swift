import Foundation

struct TaskColumnContext: Encodable {
    let value: String
    let name: String
    let dotClass: String
    let tasks: [TaskCardContext]
    let count: Int

    init(value: String, name: String, dotClass: String, tasks: [TaskCardContext]) {
        self.value = value
        self.name = name
        self.dotClass = dotClass
        self.tasks = tasks
        self.count = tasks.count
    }
}

struct TaskCardContext: Encodable {
    let id: UUID
    let boardID: UUID
    let boardName: String
    let href: String
    let title: String
    let description: String
    let hasDescription: Bool
    let statusValue: String
    let statusName: String
    let isBacklog: Bool
    let isInProgress: Bool
    let isReview: Bool
    let isDone: Bool
    let priorityValue: String
    let priorityName: String
    let isLowPriority: Bool
    let isMediumPriority: Bool
    let isHighPriority: Bool
    let isUrgentPriority: Bool
    let labels: [String]
    let labelsJoined: String
    let hasLabels: Bool
    let startInput: String
    let startDisplay: String
    let dueInput: String
    let dueDisplay: String
    let hasDueDate: Bool
    let assigneeID: String
    let assigneeName: String
    let hasAssignee: Bool
    let commentCount: Int
    let checklistCount: Int
    let completedChecklistCount: Int
    let attachmentCount: Int
    let updatedDisplay: String
    let isArchived: Bool
    let canEdit: Bool

    init(task: Task, assignee: User?, canEdit: Bool = false) throws {
        self.id = try task.requireID()
        self.boardID = task.$board.id
        self.boardName = task.$board.value?.name ?? ""
        self.href = "/app/tasks/\(try task.requireID())"
        self.title = task.title
        self.description = task.description ?? ""
        self.hasDescription = !(task.description ?? "").isEmpty
        self.statusValue = task.status.rawValue
        self.statusName = switch task.status {
        case .backlog: "Backlog"
        case .inProgress: "In progress"
        case .review: "Review"
        case .done: "Done"
        }
        self.isBacklog = task.status == .backlog
        self.isInProgress = task.status == .inProgress
        self.isReview = task.status == .review
        self.isDone = task.status == .done
        self.priorityValue = task.priority.rawValue
        self.priorityName = task.priority.rawValue.capitalized
        self.isLowPriority = task.priority == .low
        self.isMediumPriority = task.priority == .medium
        self.isHighPriority = task.priority == .high
        self.isUrgentPriority = task.priority == .urgent
        self.labels = task.labels
        self.labelsJoined = task.labels.joined(separator: ", ")
        self.hasLabels = !task.labels.isEmpty
        self.startInput = task.startAt.map(inputDate) ?? ""
        self.startDisplay = task.startAt.map(displayDateOnly) ?? "No start date"
        self.dueInput = task.dueAt.map(inputDate) ?? ""
        self.dueDisplay = task.dueAt.map(displayDateOnly) ?? "No due date"
        self.hasDueDate = task.dueAt != nil
        self.assigneeID = assignee?.id?.uuidString ?? ""
        self.assigneeName = assignee?.name ?? "Unassigned"
        self.hasAssignee = assignee != nil
        self.commentCount = task.$comments.value?.count ?? 0
        self.checklistCount = task.$checklistItems.value?.count ?? 0
        self.completedChecklistCount = task.$checklistItems.value?.filter(\.isCompleted).count ?? 0
        self.attachmentCount = task.$attachments.value?.count ?? 0
        self.updatedDisplay = task.updatedAt.map(displayDate) ?? "Recently"
        self.isArchived = task.isArchived
        self.canEdit = canEdit
    }
}

struct CalendarDayContext: Encodable {
    let day: String
    let isMuted: Bool
    let isToday: Bool
    let tasks: [TaskCardContext]
}

struct TasksPageContext: Encodable {
    let query: String
    let tasks: [TaskCardContext]
    let hasTasks: Bool

    init(query: String, tasks: [TaskCardContext]) {
        self.query = query
        self.tasks = tasks
        self.hasTasks = !tasks.isEmpty
    }
}

struct SettingsPageContext: Encodable {}

struct TaskDetailPageContext: Encodable {
    let task: TaskCardContext
    let boardName: String
    let boardHref: String
    let creatorName: String
    let canEdit: Bool
    let canComment: Bool
    let isFollowing: Bool
    let followerCount: Int
    let comments: [CommentContext]
    let hasComments: Bool
    let checklist: [ChecklistContext]
    let hasChecklist: Bool
    let attachments: [AttachmentContext]
    let hasAttachments: Bool
    let members: [MemberOptionContext]
    let properties: [TaskPropertyContext]
    let hasProperties: Bool

    init(
        task: Task,
        board: Board,
        creator: User?,
        access: BoardAccess,
        comments: [TaskComment],
        checklist: [ChecklistItem],
        attachments: [TaskAttachment],
        members: [User],
        followers: [TaskFollower],
        currentUserID: UUID
    ) throws {
        self.task = try TaskCardContext(
            task: task,
            assignee: task.$assignee.id.flatMap { id in members.first { $0.id == id } }
        )
        self.boardName = board.name
        self.boardHref = "/app/boards/\(try board.requireID())"
        self.creatorName = creator?.name ?? "Unknown"
        self.canEdit = access.isOwner || access.role.canEdit
        self.canComment = access.isOwner || access.role.canComment
        self.isFollowing = followers.contains { $0.$user.id == currentUserID }
        self.followerCount = followers.count
        self.comments = try comments.map {
            try CommentContext(
                comment: $0,
                canDelete: access.isOwner || access.role == .admin || $0.$author.id == currentUserID
            )
        }
        self.hasComments = !comments.isEmpty
        self.checklist = try checklist.map(ChecklistContext.init)
        self.hasChecklist = !checklist.isEmpty
        self.attachments = try attachments.map(AttachmentContext.init)
        self.hasAttachments = !attachments.isEmpty
        self.members = try members.map {
            try MemberOptionContext(user: $0, selectedID: task.$assignee.id)
        }
        self.properties = (board.propertyDefinitions ?? []).map { definition in
            TaskPropertyContext(
                id: definition.id,
                name: definition.name,
                value: task.properties?[definition.id] ?? "—",
                inputValue: task.properties?[definition.id] ?? ""
            )
        }
        self.hasProperties = !(board.propertyDefinitions ?? []).isEmpty
    }
}

struct CommentContext: Encodable {
    let id: UUID
    let authorName: String
    let authorAvatar: AvatarContext
    let body: String
    let createdDisplay: String
    let canDelete: Bool

    init(comment: TaskComment, canDelete: Bool) throws {
        self.id = try comment.requireID()
        self.authorName = comment.author.name
        self.authorAvatar = AvatarContext(user: comment.author)
        self.body = comment.body
        self.createdDisplay = comment.createdAt.map(displayDate) ?? "Recently"
        self.canDelete = canDelete
    }
}

struct ChecklistContext: Encodable {
    let id: UUID
    let title: String
    let isCompleted: Bool

    init(item: ChecklistItem) throws {
        self.id = try item.requireID()
        self.title = item.title
        self.isCompleted = item.isCompleted
    }
}

struct AttachmentContext: Encodable {
    let id: UUID
    let fileName: String
    let href: String
    let previewHref: String
    let sizeDisplay: String
    let isImage: Bool
    let isAudio: Bool
    let isVideo: Bool

    init(attachment: TaskAttachment) throws {
        let attachmentID = try attachment.requireID()
        let preview = attachment.preview
        self.id = attachmentID
        self.fileName = attachment.fileName
        self.href = "/app/attachments/\(attachmentID)"
        self.previewHref = "/app/attachments/\(attachmentID)/preview"
        self.sizeDisplay = ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
        self.isImage = preview?.kind == .image
        self.isAudio = preview?.kind == .audio
        self.isVideo = preview?.kind == .video
    }
}

struct MemberOptionContext: Encodable {
    let id: UUID
    let name: String
    let email: String
    let isSelected: Bool

    init(user: User, selectedID: UUID?) throws {
        self.id = try user.requireID()
        self.name = user.name
        self.email = user.email
        self.isSelected = id == selectedID
    }
}

struct TaskPropertyContext: Encodable {
    let id: String
    let name: String
    let value: String
    let inputValue: String
}

