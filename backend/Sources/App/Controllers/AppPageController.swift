import Fluent
import Foundation
import Leaf
import Vapor

struct AppPageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("app", use: overview)
        routes.get("app", "tasks", use: allTasks)
        routes.get("app", "settings", use: settings)
        routes.get("app", "boards", ":boardID", use: boardDefault)
        routes.get("app", "boards", ":boardID", "views", ":viewID", use: boardView)
        routes.get("app", "boards", ":boardID", "settings", use: boardSettings)
        routes.get("app", "tasks", ":taskID", use: taskDetail)
    }

    func overview(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let boardIDs = common.boards.map(\.id)
        let recentTasks = try await taskQuery(boardIDs: boardIDs, on: req.db)
            .sort(\.$updatedAt, .descending)
            .range(0..<8)
            .all()
        let taskContexts = try await makeTaskContexts(recentTasks, on: req.db)
        let allTasks = try await Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .all()

        return try await render(
            common: common,
            pageTitle: "Overview",
            pageKind: .overview,
            overview: OverviewPageContext(
                totalTasks: allTasks.count,
                completedTasks: allTasks.filter { $0.status == .done }.count,
                dueTasks: allTasks.filter { $0.dueAt != nil && $0.status != .done }.count,
                boardCount: common.boards.filter { !$0.isArchived }.count,
                recentTasks: taskContexts
            ),
            for: req
        )
    }

    func allTasks(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let queryText = ((try? req.query.get(String.self, at: "q")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var query = taskQuery(boardIDs: common.boards.map(\.id), on: req.db)
            .sort(\.$updatedAt, .descending)
        if !queryText.isEmpty {
            query = query.group(.or) { group in
                group.filter(\.$title ~~ queryText)
                group.filter(\.$description ~~ queryText)
            }
        }
        let tasks = try await query.all()
        return try await render(
            common: common,
            pageTitle: queryText.isEmpty ? "All tasks" : "Search",
            pageKind: .tasks,
            tasks: TasksPageContext(query: queryText, tasks: try await makeTaskContexts(tasks, on: req.db)),
            for: req
        )
    }

    func settings(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        return try await render(
            common: common,
            pageTitle: "Settings",
            pageKind: .settings,
            settings: SettingsPageContext(),
            for: req
        )
    }

    func boardDefault(req: Request) async throws -> Response {
        let access = try await boardAccess(for: req, permission: .view)
        let boardID = try access.board.requireID()
        guard let view = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .sort(\.$position, .ascending)
            .first()
        else {
            throw Abort(.notFound, reason: "This board has no views.")
        }
        return req.redirect(to: "/app/boards/\(boardID)/views/\(try view.requireID())")
    }

    func boardView(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let access = try await boardAccess(for: req, permission: .view)
        let boardID = try access.board.requireID()
        guard
            let viewID = req.parameters.get("viewID", as: UUID.self),
            let activeView = try await BoardView.query(on: req.db)
                .filter(\.$id == viewID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The view does not exist.")
        }

        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .sort(\.$position, .ascending)
            .all()
        let tasks = try await taskQuery(boardIDs: [boardID], on: req.db)
            .sort(\.$position, .ascending)
            .all()
        let defaultTemplate = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$isDefault == true)
            .first()
        let filteredTasks = apply(activeView.configuration, to: tasks)
        let taskContexts = try await makeTaskContexts(filteredTasks, on: req.db)
        let calendarMonth = requestedCalendarMonth(from: req)
        let viewPath = "/app/boards/\(boardID)/views/\(viewID)"
        let boardContext = try BoardPageContext(
            board: access.board,
            access: access,
            views: views,
            activeView: activeView,
            tasks: taskContexts,
            calendarDays: makeCalendarDays(tasks: taskContexts, monthStart: calendarMonth),
            calendarMonthLabel: calendarMonthLabel(calendarMonth),
            previousMonthHref: calendarHref(
                path: viewPath,
                month: calendarDate(byAddingMonths: -1, to: calendarMonth)
            ),
            nextMonthHref: calendarHref(
                path: viewPath,
                month: calendarDate(byAddingMonths: 1, to: calendarMonth)
            ),
            todayMonthHref: calendarHref(path: viewPath, month: calendarDate()),
            defaultTemplate: defaultTemplate
        )

        return try await render(
            common: common,
            pageTitle: access.board.name,
            pageKind: .board,
            board: boardContext,
            for: req
        )
    }

    func boardSettings(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let access = try await boardAccess(for: req, permission: .admin)
        let boardID = try access.board.requireID()
        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .sort(\.$position, .ascending)
            .all()
        let members = try await BoardMember.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .with(\.$user)
            .all()
        let templates = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .sort(\.$createdAt, .ascending)
            .all()
        let owner = if
            let ownerID = access.board.$owner.id,
            let owner = try await User.find(ownerID, on: req.db)
        {
            owner
        } else {
            try req.auth.require(User.self)
        }
        let firstViewID = try views.first?.requireID()

        return try await render(
            common: common,
            pageTitle: "\(access.board.name) settings",
            pageKind: .boardSettings,
            boardSettings: try BoardSettingsPageContext(
                board: access.board,
                views: views,
                members: members,
                templates: templates,
                owner: owner,
                firstViewID: firstViewID,
                isOwner: access.isOwner
            ),
            for: req
        )
    }

    func taskDetail(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let task = try await requiredTask(for: req, permission: .view)
        let boardID = task.$board.id
        let access = try await BoardAccessService.require(
            boardID: boardID,
            userID: try req.auth.require(User.self).requireID(),
            permission: .view,
            on: req.db
        )
        let comments = try await TaskComment.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .with(\.$author)
            .sort(\.$createdAt, .ascending)
            .all()
        let checklist = try await ChecklistItem.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .sort(\.$position, .ascending)
            .all()
        let attachments = try await TaskAttachment.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .sort(\.$createdAt, .ascending)
            .all()
        let followers = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .all()
        let members = try await boardUsers(board: access.board, on: req.db)
        let context = try TaskDetailPageContext(
            task: task,
            board: access.board,
            access: access,
            comments: comments,
            checklist: checklist,
            attachments: attachments,
            members: members,
            followers: followers,
            currentUserID: req.auth.require(User.self).requireID()
        )
        return try await render(
            common: common,
            pageTitle: task.title,
            pageKind: .taskDetail,
            taskDetail: context,
            for: req
        )
    }

    /// Builds shared navigation once for each request. A board card links to its
    /// first saved view, and an archived board remains visible in board settings.
    private func commonContext(for req: Request) async throws -> CommonPageContext {
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
            userInitials: makeInitials(for: user.name),
            boards: boardContexts
        )
    }

    private func render(
        common: CommonPageContext,
        pageTitle: String,
        pageKind: AppPageKind,
        overview: OverviewPageContext? = nil,
        board: BoardPageContext? = nil,
        tasks: TasksPageContext? = nil,
        taskDetail: TaskDetailPageContext? = nil,
        settings: SettingsPageContext? = nil,
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
                boardSettings: boardSettings
            )
        )
    }

    private func boardAccess(
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

    private func requiredTask(
        for req: Request,
        permission: BoardPermission
    ) async throws -> Task {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
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

    private func taskQuery(
        boardIDs: [UUID],
        on database: any Database
    ) -> QueryBuilder<Task> {
        Task.query(on: database)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .with(\.$board)
            .with(\.$comments)
            .with(\.$checklistItems)
            .with(\.$attachments)
    }

    private func makeTaskContexts(
        _ tasks: [Task],
        on database: any Database
    ) async throws -> [TaskCardContext] {
        var result: [TaskCardContext] = []
        for task in tasks {
            let assignee: User? = if let assigneeID = task.$assignee.id {
                try await User.find(assigneeID, on: database)
            } else {
                nil
            }
            result.append(try TaskCardContext(task: task, assignee: assignee))
        }
        return result
    }

    private func apply(
        _ configuration: BoardViewConfiguration?,
        to tasks: [Task]
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
                    comparison = left.priority.sortOrder == right.priority.sortOrder
                        ? .orderedSame
                        : left.priority.sortOrder < right.priority.sortOrder ? .orderedAscending : .orderedDescending
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

    private func boardUsers(board: Board, on database: any Database) async throws -> [User] {
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

    private func makeCalendarDays(
        tasks: [TaskCardContext],
        monthStart: Date
    ) -> [CalendarDayContext] {
        let calendar = utcCalendar()
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let gridStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: monthStart) ?? monthStart
        let activeMonth = calendar.component(.month, from: monthStart)

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let key = inputDate(date)
            return CalendarDayContext(
                day: String(calendar.component(.day, from: date)),
                isMuted: calendar.component(.month, from: date) != activeMonth,
                tasks: tasks.filter { $0.dueInput == key }
            )
        }
    }

    private func requestedCalendarMonth(from req: Request) -> Date {
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

    private func calendarDate(byAddingMonths offset: Int = 0, to date: Date = Date()) -> Date {
        let calendar = utcCalendar()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
        return calendar.date(byAdding: .month, value: offset, to: monthStart) ?? monthStart
    }

    private func calendarHref(path: String, month: Date) -> String {
        let components = utcCalendar().dateComponents([.year, .month], from: month)
        return "\(path)?month=\(components.year ?? 1970)-\(String(format: "%02d", components.month ?? 1))"
    }

    private func calendarMonthLabel(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}

extension TaskPriority {
    fileprivate var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .urgent: 3
        }
    }
}
