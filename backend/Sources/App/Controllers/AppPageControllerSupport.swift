import Fluent
import Foundation
import Leaf
import Vapor

extension AppPageController {
    /// Builds shared navigation once for each request. A board card links to its
    /// first saved view, and an archived board remains visible in board settings.
    func commonContext(for req: Request) async throws -> CommonPageContext {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        let boards = try await Board.query(on: req.db)
            .filter(\.$id ~~ boardIDs)
            .with(\.$tasks)
            .sort(\.$createdAt, .ascending)
            .all()

        var boardContexts: [BoardNavigationContext] = []
        for board in boards {
            let boardID = try board.requireID()
            let firstView = try await BoardView.query(on: req.db)
                .filter(\.$board.$id == boardID)
                .sort(\.$position, .ascending)
                .first()
            boardContexts.append(
                try BoardNavigationContext(board: board, firstViewID: firstView?.requireID())
            )
        }
        return CommonPageContext(
            csrfToken: req.csrfToken,
            userName: user.name,
            userEmail: user.email,
            userAvatar: AvatarContext(user: user),
            boards: boardContexts
        )
    }

    func render(
        common: CommonPageContext,
        pageTitle: String,
        pageKind: AppPageKind,
        overview: OverviewPageContext? = nil,
        board: BoardPageContext? = nil,
        tasks: TasksPageContext? = nil,
        taskDetail: TaskDetailPageContext? = nil,
        settings: SettingsPageContext? = nil,
        apiKeys: APIKeysPageContext? = nil,
        boardSettings: BoardSettingsPageContext? = nil,
        for req: Request
    ) async throws -> View {
        try await req.view.render(
            "app",
            AppPageContext(
                common: common,
                pageTitle: pageTitle,
                pageKind: pageKind,
                overview: overview,
                board: board,
                tasks: tasks,
                taskDetail: taskDetail,
                settings: settings,
                apiKeys: apiKeys,
                boardSettings: boardSettings
            )
        )
    }

    func boardAccess(
        for req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: try req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
    }

    func requiredTask(
        for req: Request,
        permission: BoardPermission
    ) async throws -> Task {
        guard let routeID = req.parameters.get("taskID") else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        let task: Task? = if let taskID = UUID(uuidString: routeID) {
            try await Task.find(taskID, on: req.db)
        } else if let publicID = Task.publicID(fromRouteSegment: routeID) {
            try await Task.query(on: req.db)
                .filter(\.$publicID == publicID)
                .first()
        } else {
            nil
        }
        guard let task else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: try req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
        return task
    }

    func taskQuery(
        boardIDs: [UUID],
        on database: any Database,
        isArchived: Bool = false
    ) -> QueryBuilder<Task> {
        Task.query(on: database)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == isArchived)
            .with(\.$board)
            .with(\.$comments)
            .with(\.$checklistItems)
            .with(\.$attachments)
    }

    func makeTaskContexts(
        _ tasks: [Task],
        on database: any Database,
        editPermissionUserID: UUID? = nil
    ) async throws -> [TaskCardContext] {
        var result: [TaskCardContext] = []
        var editPermissions: [UUID: Bool] = [:]
        for task in tasks {
            let assignee: User? = if let assigneeID = task.$assignee.id {
                try await User.find(assigneeID, on: database)
            } else {
                nil
            }
            let canEdit = if let userID = editPermissionUserID {
                if let cachedPermission = editPermissions[task.$board.id] {
                    cachedPermission
                } else {
                    (try? await BoardAccessService.require(
                        boardID: task.$board.id,
                        userID: userID,
                        permission: .edit,
                        on: database
                    )) != nil
                }
            } else {
                false
            }
            editPermissions[task.$board.id] = canEdit
            result.append(
                try TaskCardContext(
                    task: task,
                    assignee: assignee,
                    board: task.$board.value,
                    canEdit: canEdit
                )
            )
        }
        return result
    }

    func apply(
        _ configuration: BoardViewConfiguration?,
        to tasks: [Task],
        board: Board
    ) -> [Task] {
        guard let configuration else {
            return tasks
        }
        let filtered = configuration.filters.reduce(tasks) { current, filter in
            current.filter { task in
                switch filter.field {
                case "status":
                    task.status.rawValue == filter.value
                case "priority":
                    task.priority.rawValue == filter.value
                case "label":
                    task.labels.contains(filter.value)
                default:
                    task.properties?[filter.field] == filter.value
                }
            }
        }
        return configuration.sorts.reversed().reduce(filtered) { current, sort in
            current.sorted { left, right in
                let comparison: ComparisonResult
                switch sort.field {
                case "title":
                    comparison = left.title.localizedCaseInsensitiveCompare(right.title)
                case "due_at":
                    comparison = (left.dueAt ?? .distantFuture).compare(right.dueAt ?? .distantFuture)
                case "priority":
                    let leftOrder = board.taskSeverities.firstIndex { $0.id == left.priorityValue }
                        ?? board.taskSeverities.count
                    let rightOrder = board.taskSeverities.firstIndex { $0.id == right.priorityValue }
                        ?? board.taskSeverities.count
                    comparison = leftOrder == rightOrder
                        ? .orderedSame
                        : leftOrder < rightOrder ? .orderedAscending : .orderedDescending
                default:
                    comparison = left.position == right.position
                        ? .orderedSame
                        : left.position < right.position ? .orderedAscending : .orderedDescending
                }
                guard comparison != .orderedSame else { return false }
                return sort.direction == "descending"
                    ? comparison == .orderedDescending
                    : comparison == .orderedAscending
            }
        }
    }

    func boardUsers(board: Board, on database: any Database) async throws -> [User] {
        var users: [User] = []
        if let ownerID = board.$owner.id, let owner = try await User.find(ownerID, on: database) {
            users.append(owner)
        }
        let members = try await BoardMember.query(on: database)
            .filter(\.$board.$id == board.requireID())
            .with(\.$user)
            .all()
        users.append(contentsOf: members.map(\.user))
        return users
    }

    func makeCalendarDays(
        tasks: [TaskCardContext],
        monthStart: Date
    ) -> [CalendarDayContext] {
        let calendar = utcCalendar()
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let gridStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: monthStart) ?? monthStart
        let activeMonth = calendar.component(.month, from: monthStart)
        let todayKey = inputDate(Date())

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let key = inputDate(date)
            return CalendarDayContext(
                day: String(calendar.component(.day, from: date)),
                isMuted: calendar.component(.month, from: date) != activeMonth,
                isToday: key == todayKey,
                tasks: tasks.filter { $0.dueInput == key }
            )
        }
    }

    func requestedCalendarMonth(from req: Request) -> Date {
        guard
            let value = try? req.query.get(String.self, at: "month"),
            value.count == 7
        else {
            return calendarDate()
        }
        let parts = value.split(separator: "-")
        guard
            parts.count == 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            (1...12).contains(month),
            let date = utcCalendar().date(from: DateComponents(year: year, month: month, day: 1))
        else {
            return calendarDate()
        }
        return date
    }

    func calendarDate(byAddingMonths offset: Int = 0, to date: Date = Date()) -> Date {
        let calendar = utcCalendar()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
        return calendar.date(byAdding: .month, value: offset, to: monthStart) ?? monthStart
    }

    func calendarHref(path: String, month: Date) -> String {
        let components = utcCalendar().dateComponents([.year, .month], from: month)
        return "\(path)?month=\(components.year ?? 1970)-\(String(format: "%02d", components.month ?? 1))"
    }

    func calendarMonthLabel(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
