import Fluent
import Foundation
import Leaf
import Vapor

struct AppPageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("app", use: overview)
        routes.get("app", "tasks", use: allTasks)
        routes.get("app", "tasks", "archived", use: archivedTasks)
        routes.get("app", "settings", use: settings)
        routes.get("app", "settings", "api-keys", use: apiKeys)
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
            .with(\.$board)
            .all()

        return try await render(
            common: common,
            pageTitle: "Overview",
            pageKind: .overview,
            overview: OverviewPageContext(
                totalTasks: allTasks.count,
                completedTasks: allTasks.filter {
                    $0.$board.value?.isCompleted($0.status) ?? ($0.status == .done)
                }.count,
                dueTasks: allTasks.filter {
                    $0.dueAt != nil && !($0.$board.value?.isCompleted($0.status) ?? ($0.status == .done))
                }.count,
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

    /// Lists archived tasks separately from active search results so users can
    /// find and restore work after it leaves all active board views.
    func archivedTasks(req: Request) async throws -> View {
        let common = try await commonContext(for: req)
        let tasks = try await taskQuery(
            boardIDs: common.boards.map(\.id),
            on: req.db,
            isArchived: true
        )
        .sort(\.$updatedAt, .descending)
        .all()
        let taskContexts = try await makeTaskContexts(
            tasks,
            on: req.db,
            editPermissionUserID: req.auth.require(User.self).requireID()
        )

        return try await render(
            common: common,
            pageTitle: "Archived tasks",
            pageKind: .archivedTasks,
            tasks: TasksPageContext(query: "", tasks: taskContexts),
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

    func apiKeys(req: Request) async throws -> View {
        try await renderAPIKeysPage(for: req)
    }

    /// Renders key management after GET requests and direct POST responses. The
    /// created secret stays in request memory and is never stored in a session.
    func renderAPIKeysPage(
        for req: Request,
        createdKey: String? = nil,
        error: String? = nil
    ) async throws -> View {
        let common = try await commonContext(for: req)
        let userID = try req.auth.require(User.self).requireID()
        let credentials = try await APIKeyCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .all()
        return try await render(
            common: common,
            pageTitle: "API keys",
            pageKind: .apiKeys,
            apiKeys: try APIKeysPageContext(
                credentials: credentials,
                apiBaseURL: apiBaseURL(for: req),
                createdKey: createdKey,
                error: error
            ),
            for: req
        )
    }

    /// Uses the proxy scheme when Railway terminates TLS, then uses the request
    /// host so documentation examples match the domain that the user opened.
    private func apiBaseURL(for req: Request) -> String {
        let scheme = req.headers.first(name: "X-Forwarded-Proto")?
            .split(separator: ",")
            .first
            .map(String.init)
            ?? (req.application.environment == .production ? "https" : "http")
        let host = req.headers.first(name: .host) ?? "localhost:8080"
        return "\(scheme)://\(host)/api/v1"
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
        let filteredTasks = apply(activeView.configuration, to: tasks, board: access.board)
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

    func taskDetail(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .view)
        guard req.url.path == task.browserPath else {
            return req.redirect(to: task.browserPath, redirectType: .permanent)
        }
        let common = try await commonContext(for: req)
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
        let creator: User? = if let creatorID = task.$creator.id {
            try await User.find(creatorID, on: req.db)
        } else {
            nil
        }
        let context = try TaskDetailPageContext(
            task: task,
            board: access.board,
            creator: creator,
            access: access,
            comments: comments,
            checklist: checklist,
            attachments: attachments,
            members: members,
            followers: followers,
            currentUserID: req.auth.require(User.self).requireID()
        )
        let view = try await render(
            common: common,
            pageTitle: task.title,
            pageKind: .taskDetail,
            taskDetail: context,
            for: req
        )
        return try await view.encodeResponse(for: req)
    }
}
