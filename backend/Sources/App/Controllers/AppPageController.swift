import Fluent
import Foundation
import Vapor

struct AppPageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: overview)
        routes.get("semester", use: semester)
        routes.get("tasks", use: allTasks)
        routes.get("tasks", "archived", use: archivedTasks)
        routes.get("settings", use: settings)
        routes.get("settings", "api-keys", use: apiKeys)
        routes.get("settings", "integrations", use: integrations)
        routes.get("boards", ":boardID", use: boardDefault)
        routes.get("boards", ":boardID", "views", ":viewID", use: boardView)
        routes.get("boards", ":boardID", "settings", use: boardSettings)
        routes.get("tasks", ":taskID", use: taskDetail)
    }

    func overview(req: Request) async throws -> Response {
        let common = try await commonContext(for: req)
        let boardIDs = common.boards.map(\.id)
        let requestedCourseID = (try? req.query.get(String.self, at: "course"))
            .flatMap(UUID.init(uuidString:))
        let selectedCourseID = requestedCourseID.flatMap { courseID in
            common.boards.contains { $0.id == courseID && !$0.isArchived } ? courseID : nil
        }
        let tasks = try await taskQuery(boardIDs: boardIDs, on: req.db)
            .sort(\.$dueAt, .ascending)
            .all()
        let taskContexts = try await makeTaskContexts(tasks, on: req.db)
        let taskIDs = taskContexts.map(\.id)
        let studySessions = if taskIDs.isEmpty {
            [StudySession]()
        } else {
            try await StudySession.query(on: req.db)
                .filter(\.$user.$id == req.auth.require(User.self).requireID())
                .filter(\.$task.$id ~~ taskIDs)
                .all()
        }

        return try respond(
            common: common,
            pageTitle: "This week",
            pageKind: .overview,
            overview: OverviewPageContext(
                tasks: taskContexts,
                courses: common.boards,
                selectedCourseID: selectedCourseID,
                studySessions: studySessions,
                timeZoneIdentifier: common.userTimeZone
            ),
        )
    }

    /// Builds one cross-course horizon from existing deadlines. The view stays
    /// read-only because students plan individual work days from the weekly page.
    func semester(req: Request) async throws -> Response {
        let common = try await commonContext(for: req)
        let tasks = try await taskQuery(boardIDs: common.boards.map(\.id), on: req.db)
            .sort(\.$dueAt, .ascending)
            .all()
        return try respond(
            common: common,
            pageTitle: "Semester",
            pageKind: .semester,
            semester: SemesterPageContext(
                tasks: try await makeTaskContexts(tasks, on: req.db),
                courses: common.boards,
                timeZoneIdentifier: common.userTimeZone
            )
        )
    }

    func allTasks(req: Request) async throws -> Response {
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
        return try respond(
            common: common,
            pageTitle: queryText.isEmpty ? "All assignments" : "Search",
            pageKind: .tasks,
            tasks: TasksPageContext(query: queryText, tasks: try await makeTaskContexts(tasks, on: req.db)),
        )
    }

    /// Lists archived tasks separately from active search results so users can
    /// find and restore work after it leaves all active board views.
    func archivedTasks(req: Request) async throws -> Response {
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

        return try respond(
            common: common,
            pageTitle: "Archived assignments",
            pageKind: .archivedTasks,
            tasks: TasksPageContext(query: "", tasks: taskContexts),
        )
    }

    func settings(req: Request) async throws -> Response {
        let common = try await commonContext(for: req)
        let userID = try req.auth.require(User.self).requireID()
        let calendarFeed = try await CalendarFeedCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        return try respond(
            common: common,
            pageTitle: "Settings",
            pageKind: .settings,
            settings: SettingsPageContext(
                notificationsAvailable: req.application.notificationConfiguration != nil,
                calendarFeed: CalendarFeedStatusResponse(credential: calendarFeed)
            ),
        )
    }

    func apiKeys(req: Request) async throws -> Response {
        try await renderAPIKeysPage(for: req)
    }

    func integrations(req: Request) async throws -> Response {
        let common = try await commonContext(for: req)
        let connections = try await CanvasConnection.query(on: req.db)
            .filter(\.$user.$id == req.auth.require(User.self).requireID())
            .sort(\.$createdAt, .descending)
            .all()
        let baseURL = apiBaseURL(for: req)
        let focalpointOrigin = String(baseURL.dropLast("/api/v1".count))
        return try respond(
            common: common,
            pageTitle: "Integrations",
            pageKind: .integrations,
            integrations: try CanvasIntegrationsPageContext(
                connections: connections,
                focalpointOrigin: focalpointOrigin
            )
        )
    }

    /// Returns key management data. A created secret is included only in the
    /// response to the request that created it and is never stored in a session.
    func renderAPIKeysPage(
        for req: Request,
        createdKey: String? = nil,
        error: String? = nil
    ) async throws -> Response {
        let common = try await commonContext(for: req)
        let userID = try req.auth.require(User.self).requireID()
        let credentials = try await APIKeyCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .all()
        return try respond(
            common: common,
            pageTitle: "API keys",
            pageKind: .apiKeys,
            apiKeys: try APIKeysPageContext(
                credentials: credentials,
                apiBaseURL: apiBaseURL(for: req),
                createdKey: createdKey,
                error: error
            ),
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
        let host = req.headers.first(name: "X-Forwarded-Host")?
            .split(separator: ",")
            .first
            .map(String.init)
            ?? req.headers.first(name: .host)
            ?? "localhost:5173"
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
        return try jsonResponse(
            BoardDefaultViewContext(
                href: "/app/boards/\(boardID)/views/\(try view.requireID())"
            )
        )
    }

    func boardView(req: Request) async throws -> Response {
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
        let canvasLink = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .with(\.$connection)
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
            defaultTemplate: defaultTemplate,
            canvasLink: canvasLink,
            canvasConnection: canvasLink?.connection
        )

        return try respond(
            common: common,
            pageTitle: access.board.name,
            pageKind: .board,
            board: boardContext,
        )
    }

    func boardSettings(req: Request) async throws -> Response {
        try await renderBoardSettingsPage(for: req)
    }

    /// Builds board administration and Tap capability state for the SSR frontend.
    func renderBoardSettingsPage(
        for req: Request,
        createdTapURL: String? = nil,
        tapError: String? = nil
    ) async throws -> Response {
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
        let tapTasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .filter(\.$isArchived == false)
            .sort(\.$title, .ascending)
            .all()
        let tapActions = try await TapAction.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .with(\.$targetTask)
            .sort(\.$createdAt, .descending)
            .all()
        let tapActionIDs = try tapActions.map { try $0.requireID() }
        let tapExecutions: [TapExecution] = if tapActionIDs.isEmpty {
            []
        } else {
            try await TapExecution.query(on: req.db)
                .filter(\.$action.$id ~~ tapActionIDs)
                .sort(\.$createdAt, .descending)
                .range(0..<20)
                .all()
        }
        let owner = if
            let ownerID = access.board.$owner.id,
            let owner = try await User.find(ownerID, on: req.db)
        {
            owner
        } else {
            try req.auth.require(User.self)
        }
        let firstViewID = try views.first?.requireID()
        let canvasLink = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .first()

        return try respond(
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
                isOwner: access.isOwner,
                tapTasks: tapTasks,
                tapActions: tapActions,
                tapExecutions: tapExecutions,
                createdTapURL: createdTapURL,
                tapError: tapError,
                canvasLink: canvasLink
            ),
        )
    }

    func taskDetail(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .view)
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
        let currentUserID = try req.auth.require(User.self).requireID()
        let reminders = try await TaskReminder.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .filter(\.$user.$id == currentUserID)
            .filter(\.$queuedAt == nil)
            .sort(\.$remindAt, .ascending)
            .all()
        let members = try await boardUsers(board: access.board, on: req.db)
        let creator: User? = if let creatorID = task.$creator.id {
            try await User.find(creatorID, on: req.db)
        } else {
            nil
        }
        let canvasLink = try await CanvasAssignmentLink.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .with(\.$courseLink) { courseLink in
                courseLink.with(\.$connection)
            }
            .first()
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
            reminders: reminders,
            notificationsEnabled: req.application.notificationConfiguration != nil,
            currentUserID: currentUserID,
            canvasLink: canvasLink,
            canvasConnection: canvasLink?.courseLink.connection
        )
        return try respond(
            common: common,
            pageTitle: task.title,
            pageKind: .taskDetail,
            taskDetail: context,
        )
    }
}

private struct BoardDefaultViewContext: Encodable {
    let href: String
}
