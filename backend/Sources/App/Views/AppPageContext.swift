import Foundation

enum AppPageKind {
    case overview
    case board
    case tasks
    case archivedTasks
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
    let isActiveTasks: Bool
    let isArchivedTasks: Bool
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
        self.isTasks = pageKind == .tasks || pageKind == .archivedTasks
        self.isActiveTasks = pageKind == .tasks
        self.isArchivedTasks = pageKind == .archivedTasks
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
    let userAvatar: AvatarContext
    let boards: [BoardNavigationContext]
}

/// Supplies one image-or-initials choice to Leaf wherever a user identity appears.
/// OAuth URLs are validated before storage, so templates only select the display.
struct AvatarContext: Encodable {
    let initials: String
    let profilePictureURL: String
    let hasProfilePicture: Bool

    init(user: User) {
        self.initials = makeInitials(for: user.name)
        self.profilePictureURL = user.profilePictureURL ?? ""
        self.hasProfilePicture = user.profilePictureURL != nil
    }
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
    let calendarMonthLabel: String
    let previousMonthHref: String
    let nextMonthHref: String
    let todayMonthHref: String
    let hasDefaultTemplate: Bool
    let defaultTemplateName: String
    let newTaskTitle: String
    let newTaskDescription: String
    let newTaskStatus: String
    let newTaskStatusName: String
    let newTaskPriority: String
    let newTaskPriorityName: String
    let newTaskLabels: String
    let newTaskIsBacklog: Bool
    let newTaskIsInProgress: Bool
    let newTaskIsReview: Bool
    let newTaskIsDone: Bool
    let newTaskIsLowPriority: Bool
    let newTaskIsMediumPriority: Bool
    let newTaskIsHighPriority: Bool
    let newTaskIsUrgentPriority: Bool

    init(
        board: Board,
        access: BoardAccess,
        views: [BoardView],
        activeView: BoardView,
        tasks: [TaskCardContext],
        calendarDays: [CalendarDayContext],
        calendarMonthLabel: String,
        previousMonthHref: String,
        nextMonthHref: String,
        todayMonthHref: String,
        defaultTemplate: TaskTemplate?
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
        self.calendarMonthLabel = calendarMonthLabel
        self.previousMonthHref = previousMonthHref
        self.nextMonthHref = nextMonthHref
        self.todayMonthHref = todayMonthHref
        self.hasDefaultTemplate = defaultTemplate != nil
        self.defaultTemplateName = defaultTemplate?.name ?? ""
        self.newTaskTitle = defaultTemplate?.title ?? ""
        self.newTaskDescription = defaultTemplate?.description ?? ""
        let defaultStatus = defaultTemplate?.status ?? .backlog
        self.newTaskStatus = defaultStatus.rawValue
        self.newTaskStatusName = defaultStatus.displayName
        let defaultPriority = defaultTemplate?.priority ?? .medium
        self.newTaskPriority = defaultPriority.rawValue
        self.newTaskPriorityName = defaultPriority.rawValue.capitalized
        self.newTaskLabels = defaultTemplate?.labels.joined(separator: ", ") ?? ""
        self.newTaskIsBacklog = defaultStatus == .backlog
        self.newTaskIsInProgress = defaultStatus == .inProgress
        self.newTaskIsReview = defaultStatus == .review
        self.newTaskIsDone = defaultStatus == .done
        self.newTaskIsLowPriority = defaultPriority == .low
        self.newTaskIsMediumPriority = defaultPriority == .medium
        self.newTaskIsHighPriority = defaultPriority == .high
        self.newTaskIsUrgentPriority = defaultPriority == .urgent
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
