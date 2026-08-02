import Foundation

struct BoardSettingsPageContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let firstViewHref: String
    let isOwner: Bool
    let isArchived: Bool
    let ownerName: String
    let ownerEmail: String
    let ownerAvatar: AvatarContext
    let views: [BoardSettingsViewContext]
    let members: [BoardMemberContext]
    let templates: [TemplateContext]
    let properties: [PropertyDefinitionContext]
    let statuses: [TaskOptionContext]
    let severities: [TaskOptionContext]
    let defaultTapStatus: String
    let defaultTapStatusName: String
    let defaultTapSeverity: String
    let defaultTapSeverityName: String
    let tapTasks: [TapTaskOptionContext]
    let tapActions: [TapActionContext]
    let tapExecutions: [TapExecutionContext]
    let hasTapTasks: Bool
    let hasTapActions: Bool
    let hasTapExecutions: Bool
    let createdTapURL: String
    let createdTapURLByteCount: Int
    let hasCreatedTapURL: Bool
    let tapError: String
    let hasTapError: Bool

    init(
        board: Board,
        views: [BoardView],
        members: [BoardMember],
        templates: [TaskTemplate],
        owner: User,
        firstViewID: UUID?,
        isOwner: Bool,
        tapTasks: [Task],
        tapActions: [TapAction],
        tapExecutions: [TapExecution],
        createdTapURL: String?,
        tapError: String?
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
        self.ownerName = owner.name
        self.ownerEmail = owner.email
        self.ownerAvatar = AvatarContext(user: owner)
        self.views = try views.map(BoardSettingsViewContext.init)
        self.members = try members.map(BoardMemberContext.init)
        self.templates = try templates.map(TemplateContext.init)
        self.properties = (board.propertyDefinitions ?? []).map(PropertyDefinitionContext.init)
        let defaultStatus = board.taskStatuses.first ?? BoardTaskOption.defaultStatuses[0]
        let defaultSeverity = board.taskSeverities.first ?? BoardTaskOption.defaultSeverities[0]
        self.statuses = board.taskStatuses.map {
            TaskOptionContext(option: $0, selectedValue: defaultStatus.id)
        }
        self.severities = board.taskSeverities.map {
            TaskOptionContext(option: $0, selectedValue: defaultSeverity.id)
        }
        self.defaultTapStatus = defaultStatus.id
        self.defaultTapStatusName = defaultStatus.name
        self.defaultTapSeverity = defaultSeverity.id
        self.defaultTapSeverityName = defaultSeverity.name
        self.tapTasks = try tapTasks.map { try TapTaskOptionContext(task: $0) }
        self.tapActions = try tapActions.map { try TapActionContext(action: $0, board: board, tasks: tapTasks) }
        self.tapExecutions = tapExecutions.map(TapExecutionContext.init)
        self.hasTapTasks = !tapTasks.isEmpty
        self.hasTapActions = !tapActions.isEmpty
        self.hasTapExecutions = !tapExecutions.isEmpty
        self.createdTapURL = createdTapURL ?? ""
        self.createdTapURLByteCount = createdTapURL?.utf8.count ?? 0
        self.hasCreatedTapURL = createdTapURL != nil
        self.tapError = tapError ?? ""
        self.hasTapError = tapError != nil
    }
}

struct TapTaskOptionContext: Encodable {
    let id: UUID
    let title: String
    let isSelected: Bool

    init(task: Task, selectedID: UUID? = nil) throws {
        self.id = try task.requireID()
        self.title = task.title
        self.isSelected = task.id == selectedID
    }
}

struct TapActionContext: Encodable {
    let id: UUID
    let name: String
    let prefix: String
    let kind: String
    let kindName: String
    let isCreateTask: Bool
    let isUpdateTask: Bool
    let isEnabled: Bool
    let isActive: Bool
    let stateName: String
    let summary: String
    let title: String
    let description: String
    let status: String
    let statusName: String
    let severity: String
    let severityName: String
    let targetTaskID: String
    let targetTaskName: String
    let statusOptions: [TaskOptionContext]
    let severityOptions: [TaskOptionContext]
    let tasks: [TapTaskOptionContext]
    let labels: String
    let expiresAtInput: String
    let expiresAtLabel: String
    let maxUses: String
    let useCount: Int
    let useLimitLabel: String
    let cooldownSeconds: Int
    let lastUsedAt: String

    init(action: TapAction, board: Board, tasks: [Task]) throws {
        let now = Date()
        let isExpired = action.expiresAt.map { $0 <= now } ?? false
        let isExhausted = action.maxUses.map { action.useCount >= $0 } ?? false
        let targetTask = action.$targetTask.value ?? nil
        self.id = try action.requireID()
        self.name = action.name
        self.prefix = action.tokenPrefix
        self.kind = action.kind.rawValue
        self.kindName = action.kind == .createTask ? "Create task" : "Update task"
        self.isCreateTask = action.kind == .createTask
        self.isUpdateTask = action.kind == .updateTask
        self.isEnabled = action.isEnabled
        self.isActive = action.isEnabled && !isExpired && !isExhausted
        self.stateName = if !action.isEnabled {
            "Disabled"
        } else if isExpired {
            "Expired"
        } else if isExhausted {
            "Use limit reached"
        } else {
            "Active"
        }
        self.summary = if action.kind == .createTask {
            "Create “\(action.configuration.title ?? "task")”"
        } else {
            "Set \(targetTask?.title ?? "missing task") to \(board.statusOption(for: TaskStatus(rawValue: action.configuration.status)).name)"
        }
        self.title = action.configuration.title ?? ""
        self.description = action.configuration.description ?? ""
        self.status = action.configuration.status
        self.statusName = board.statusOption(
            for: TaskStatus(rawValue: action.configuration.status)
        ).name
        let severity = action.configuration.priority ?? TaskPriority.medium.rawValue
        self.severity = severity
        self.severityName = board.severityOption(
            for: TaskPriority(rawValue: severity)
        ).name
        self.targetTaskID = action.$targetTask.id?.uuidString ?? ""
        self.targetTaskName = targetTask?.title ?? "Select a task"
        self.statusOptions = board.taskStatuses.map {
            TaskOptionContext(option: $0, selectedValue: action.configuration.status)
        }
        self.severityOptions = board.taskSeverities.map {
            TaskOptionContext(option: $0, selectedValue: action.configuration.priority)
        }
        self.tasks = try tasks.map {
            try TapTaskOptionContext(task: $0, selectedID: action.$targetTask.id)
        }
        self.labels = action.configuration.labels.joined(separator: ", ")
        self.expiresAtInput = action.expiresAt.map(inputDate) ?? ""
        self.expiresAtLabel = action.expiresAt.map(displayDateOnly) ?? "Never"
        self.maxUses = action.maxUses.map(String.init) ?? ""
        self.useCount = action.useCount
        self.useLimitLabel = action.maxUses.map { "\(action.useCount) of \($0) uses" }
            ?? "\(action.useCount) uses"
        self.cooldownSeconds = action.cooldownSeconds
        self.lastUsedAt = action.lastUsedAt.map(displayDate) ?? "Never"
    }
}

struct TapExecutionContext: Encodable {
    let actionName: String
    let message: String
    let createdAt: String

    init(execution: TapExecution) {
        self.actionName = execution.actionName
        self.message = execution.message
        self.createdAt = execution.createdAt.map(displayDate) ?? "Just now"
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
        self.groupByName = self.groupBy == "priority" ? "Severity" : "Status"
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
    let avatar: AvatarContext

    init(member: BoardMember) throws {
        self.id = try member.requireID()
        self.name = member.user.name
        self.email = member.user.email
        self.role = member.role.rawValue.capitalized
        self.avatar = AvatarContext(user: member.user)
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
    let detail: String

    init(definition: BoardPropertyDefinition) {
        self.id = definition.id
        self.name = definition.name
        self.typeName = definition.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        self.detail = definition.options.isEmpty
            ? typeName
            : "\(typeName) · \(definition.options.map(\.name).joined(separator: ", "))"
    }
}

func makeInitials(for name: String) -> String {
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
