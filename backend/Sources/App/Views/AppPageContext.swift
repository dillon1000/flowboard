import Foundation

enum AppPageKind {
    case overview
    case board
    case tasks
    case taskDetail
    case settings
    case boardSettings
}

struct AppPageContext: Encodable {
    let common: CommonPageContext
    let pageTitle: String
    let documentTitle: String
    let isOverview: Bool
    let isBoard: Bool
    let isTasks: Bool
    let isTaskDetail: Bool
    let isSettings: Bool
    let isBoardSettings: Bool
    let overview: OverviewPageContext?
    let board: BoardPageContext?
    let tasks: TasksPageContext?
    let taskDetail: TaskDetailPageContext?
    let settings: SettingsPageContext?
    let boardSettings: BoardSettingsPageContext?

    init(
        common: CommonPageContext,
        pageTitle: String,
        pageKind: AppPageKind,
        overview: OverviewPageContext?,
        board: BoardPageContext?,
        tasks: TasksPageContext?,
        taskDetail: TaskDetailPageContext?,
        settings: SettingsPageContext?,
        boardSettings: BoardSettingsPageContext?
    ) {
        self.common = common
        self.pageTitle = pageTitle
        self.documentTitle = "\(pageTitle) · Flowboard"
        self.isOverview = pageKind == .overview
        self.isBoard = pageKind == .board
        self.isTasks = pageKind == .tasks
        self.isTaskDetail = pageKind == .taskDetail
        self.isSettings = pageKind == .settings
        self.isBoardSettings = pageKind == .boardSettings
        self.overview = overview
        self.board = board
        self.tasks = tasks
        self.taskDetail = taskDetail
        self.settings = settings
        self.boardSettings = boardSettings
    }
}

struct CommonPageContext: Encodable {
    let csrfToken: String
    let userName: String
    let userEmail: String
    let userInitials: String
    let boards: [BoardNavigationContext]
}

struct BoardNavigationContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let href: String
    let taskCount: Int
    let completedCount: Int
    let isArchived: Bool

    init(board: Board, firstViewID: UUID?) throws {
        let id = try board.requireID()
        self.id = id
        self.name = board.name
        self.description = board.description ?? "No description"
        self.href = if let firstViewID {
            "/app/boards/\(id)/views/\(firstViewID)"
        } else {
            "/app/boards/\(id)"
        }
        self.taskCount = board.tasks.filter { !$0.isArchived }.count
        self.completedCount = board.tasks.filter { !$0.isArchived && $0.status == .done }.count
        self.isArchived = board.isArchived
    }
}

struct OverviewPageContext: Encodable {
    let totalTasks: Int
    let completedTasks: Int
    let dueTasks: Int
    let boardCount: Int
    let recentTasks: [TaskCardContext]
    let hasRecentTasks: Bool

    init(
        totalTasks: Int,
        completedTasks: Int,
        dueTasks: Int,
        boardCount: Int,
        recentTasks: [TaskCardContext]
    ) {
        self.totalTasks = totalTasks
        self.completedTasks = completedTasks
        self.dueTasks = dueTasks
        self.boardCount = boardCount
        self.recentTasks = recentTasks
        self.hasRecentTasks = !recentTasks.isEmpty
    }
}

struct BoardPageContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let role: String
    let canEdit: Bool
    let isOwner: Bool
    let views: [BoardViewTabContext]
    let activeView: BoardViewTabContext
    let tasks: [TaskCardContext]
    let hasTasks: Bool
    let groupByName: String
    let hasFilters: Bool
    let filterSummary: String
    let hasSorts: Bool
    let sortSummary: String
    let canDrag: Bool
    let columns: [TaskColumnContext]
    let calendarDays: [CalendarDayContext]

    init(
        board: Board,
        access: BoardAccess,
        views: [BoardView],
        activeView: BoardView,
        tasks: [TaskCardContext],
        calendarDays: [CalendarDayContext]
    ) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.description = board.description ?? ""
        self.role = access.isOwner ? "Owner" : access.role.rawValue.capitalized
        self.canEdit = access.isOwner || access.role.canEdit
        self.isOwner = access.isOwner
        self.views = try views.map {
            try BoardViewTabContext(view: $0, boardID: board.requireID(), activeID: activeView.requireID())
        }
        self.activeView = try BoardViewTabContext(
            view: activeView,
            boardID: board.requireID(),
            activeID: activeView.requireID()
        )
        self.tasks = tasks
        self.hasTasks = !tasks.isEmpty
        let configuration = activeView.configuration
        let groupBy = configuration?.groupBy ?? "status"
        self.groupByName = groupBy == "priority" ? "Priority" : "Status"
        self.hasFilters = !(configuration?.filters.isEmpty ?? true)
        self.filterSummary = configuration?.filters.first.map {
            "\($0.field.replacingOccurrences(of: "_", with: " ").capitalized): \($0.value)"
        } ?? ""
        self.hasSorts = !(configuration?.sorts.isEmpty ?? true)
        self.sortSummary = configuration?.sorts.first.map {
            "\($0.field.replacingOccurrences(of: "_", with: " ").capitalized) \($0.direction)"
        } ?? ""
        self.canDrag = canEdit && activeView.type == .board && groupBy == "status"
        self.columns = if groupBy == "priority" {
            TaskPriority.allCases.map { priority in
                TaskColumnContext(
                    value: priority.rawValue,
                    name: priority.rawValue.capitalized,
                    dotClass: priority.rawValue,
                    tasks: tasks.filter { $0.priorityValue == priority.rawValue }
                )
            }
        } else {
            TaskStatus.allCases.map { status in
                TaskColumnContext(
                    value: status.rawValue,
                    name: status.displayName,
                    dotClass: status.dotClass,
                    tasks: tasks.filter { $0.statusValue == status.rawValue }
                )
            }
        }
        self.calendarDays = calendarDays
    }
}

struct BoardViewTabContext: Encodable {
    let id: UUID
    let name: String
    let type: String
    let href: String
    let isActive: Bool
    let isBoard: Bool
    let isTable: Bool
    let isCalendar: Bool
    let isGallery: Bool
    let icon: String

    init(view: BoardView, boardID: UUID, activeID: UUID) throws {
        let id = try view.requireID()
        self.id = id
        self.name = view.name
        self.type = view.type.rawValue
        self.href = "/app/boards/\(boardID)/views/\(id)"
        self.isActive = id == activeID
        self.isBoard = view.type == .board
        self.isTable = view.type == .table
        self.isCalendar = view.type == .calendar
        self.isGallery = view.type == .gallery
        self.icon = switch view.type {
        case .board: "columns-3"
        case .table: "table-2"
        case .calendar: "calendar-days"
        case .gallery: "gallery-horizontal-end"
        }
    }
}

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
    let dueInput: String
    let dueDisplay: String
    let hasDueDate: Bool
    let assigneeName: String
    let hasAssignee: Bool
    let commentCount: Int
    let checklistCount: Int
    let completedChecklistCount: Int
    let attachmentCount: Int
    let updatedDisplay: String

    init(task: Task, assignee: User?) throws {
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
        self.dueInput = task.dueAt.map(inputDate) ?? ""
        self.dueDisplay = task.dueAt.map(displayDateOnly) ?? "No due date"
        self.hasDueDate = task.dueAt != nil
        self.assigneeName = assignee?.name ?? "Unassigned"
        self.hasAssignee = assignee != nil
        self.commentCount = task.$comments.value?.count ?? 0
        self.checklistCount = task.$checklistItems.value?.count ?? 0
        self.completedChecklistCount = task.$checklistItems.value?.filter(\.isCompleted).count ?? 0
        self.attachmentCount = task.$attachments.value?.count ?? 0
        self.updatedDisplay = task.updatedAt.map(displayDate) ?? "Recently"
    }
}

struct CalendarDayContext: Encodable {
    let day: String
    let isMuted: Bool
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
    let canEdit: Bool
    let canComment: Bool
    let isFollowing: Bool
    let followerCount: Int
    let comments: [CommentContext]
    let checklist: [ChecklistContext]
    let attachments: [AttachmentContext]
    let members: [MemberOptionContext]
    let properties: [TaskPropertyContext]

    init(
        task: Task,
        board: Board,
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
        self.canEdit = access.isOwner || access.role.canEdit
        self.canComment = access.isOwner || access.role.canComment
        self.isFollowing = followers.contains { $0.$user.id == currentUserID }
        self.followerCount = followers.count
        self.comments = try comments.map(CommentContext.init)
        self.checklist = try checklist.map(ChecklistContext.init)
        self.attachments = try attachments.map(AttachmentContext.init)
        self.members = try members.map(MemberOptionContext.init)
        self.properties = (board.propertyDefinitions ?? []).map { definition in
            TaskPropertyContext(
                id: definition.id,
                name: definition.name,
                value: task.properties?[definition.id] ?? "—"
            )
        }
    }
}

struct CommentContext: Encodable {
    let id: UUID
    let authorName: String
    let authorInitials: String
    let body: String
    let createdDisplay: String

    init(comment: TaskComment) throws {
        self.id = try comment.requireID()
        self.authorName = comment.author.name
        self.authorInitials = initials(for: comment.author.name)
        self.body = comment.body
        self.createdDisplay = comment.createdAt.map(displayDate) ?? "Recently"
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
    let sizeDisplay: String

    init(attachment: TaskAttachment) throws {
        self.id = try attachment.requireID()
        self.fileName = attachment.fileName
        self.href = "/app/attachments/\(try attachment.requireID())"
        self.sizeDisplay = ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
    }
}

struct MemberOptionContext: Encodable {
    let id: UUID
    let name: String
    let email: String

    init(user: User) throws {
        self.id = try user.requireID()
        self.name = user.name
        self.email = user.email
    }
}

struct TaskPropertyContext: Encodable {
    let id: String
    let name: String
    let value: String
}

struct BoardSettingsPageContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let firstViewHref: String
    let isOwner: Bool
    let isArchived: Bool
    let views: [BoardSettingsViewContext]
    let members: [BoardMemberContext]
    let templates: [TemplateContext]
    let properties: [PropertyDefinitionContext]

    init(
        board: Board,
        views: [BoardView],
        members: [BoardMember],
        templates: [TaskTemplate],
        firstViewID: UUID?,
        isOwner: Bool
    ) throws {
        let boardID = try board.requireID()
        self.id = boardID
        self.name = board.name
        self.description = board.description ?? ""
        self.firstViewHref = if let firstViewID {
            "/app/boards/\(boardID)/views/\(firstViewID)"
        } else {
            "/app/boards/\(boardID)"
        }
        self.isOwner = isOwner
        self.isArchived = board.isArchived
        self.views = try views.map(BoardSettingsViewContext.init)
        self.members = try members.map(BoardMemberContext.init)
        self.templates = try templates.map(TemplateContext.init)
        self.properties = (board.propertyDefinitions ?? []).map(PropertyDefinitionContext.init)
    }
}

struct BoardSettingsViewContext: Encodable {
    let id: UUID
    let name: String
    let typeName: String
    let groupBy: String
    let groupByName: String
    let isGroupedByStatus: Bool
    let isGroupedByPriority: Bool
    let filterField: String
    let filterValue: String
    let sortField: String
    let sortDirection: String
    let isAscending: Bool
    let isDescending: Bool

    init(view: BoardView) throws {
        self.id = try view.requireID()
        self.name = view.name
        self.typeName = view.type.rawValue.capitalized
        self.groupBy = view.configuration?.groupBy ?? "status"
        self.groupByName = self.groupBy == "priority" ? "Priority" : "Status"
        self.isGroupedByStatus = self.groupBy == "status"
        self.isGroupedByPriority = self.groupBy == "priority"
        self.filterField = view.configuration?.filters.first?.field ?? ""
        self.filterValue = view.configuration?.filters.first?.value ?? ""
        self.sortField = view.configuration?.sorts.first?.field ?? ""
        self.sortDirection = view.configuration?.sorts.first?.direction ?? "ascending"
        self.isAscending = self.sortDirection == "ascending"
        self.isDescending = self.sortDirection == "descending"
    }
}

struct BoardMemberContext: Encodable {
    let id: UUID
    let name: String
    let email: String
    let role: String

    init(member: BoardMember) throws {
        self.id = try member.requireID()
        self.name = member.user.name
        self.email = member.user.email
        self.role = member.role.rawValue.capitalized
    }
}

struct TemplateContext: Encodable {
    let id: UUID
    let name: String
    let title: String
    let isDefault: Bool

    init(template: TaskTemplate) throws {
        self.id = try template.requireID()
        self.name = template.name
        self.title = template.title
        self.isDefault = template.isDefault
    }
}

struct PropertyDefinitionContext: Encodable {
    let id: String
    let name: String
    let typeName: String

    init(definition: BoardPropertyDefinition) {
        self.id = definition.id
        self.name = definition.name
        self.typeName = definition.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func initials(for name: String) -> String {
    String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
}

func inputDate(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}

func displayDateOnly(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMM d, yyyy"
    return formatter.string(from: date)
}

func displayDate(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().year())
}

private extension TaskStatus {
    var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .inProgress: "In progress"
        case .review: "Review"
        case .done: "Done"
        }
    }

    var dotClass: String {
        switch self {
        case .backlog: ""
        case .inProgress: "progress"
        case .review: "review"
        case .done: "done"
        }
    }
}
