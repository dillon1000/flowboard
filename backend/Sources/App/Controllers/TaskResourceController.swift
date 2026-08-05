import Fluent
import Vapor

/// Exposes task-owned collaboration records. Every handler resolves the parent
/// task and its board permission before it reads or changes the child resource.
struct TaskResourceController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let task = routes.grouped("tasks", ":taskID")

        let comments = task.grouped("comments")
        comments.get(use: listComments)
        comments.post(use: createComment)
        comments.patch(":commentID", use: updateComment)
        comments.delete(":commentID", use: deleteComment)

        let checklist = task.grouped("checklist")
        checklist.get(use: listChecklist)
        checklist.post(use: createChecklistItem)
        checklist.patch(":itemID", use: updateChecklistItem)
        checklist.post(":itemID", "move", use: moveChecklistItem)
        checklist.delete(":itemID", use: deleteChecklistItem)

        let followers = task.grouped("followers")
        followers.get(use: listFollowers)
        followers.post("me", use: follow)
        followers.delete("me", use: unfollow)

        let reminders = task.grouped("reminders")
        reminders.get(use: listReminders)
        reminders.post(use: createReminder)
        reminders.delete(":reminderID", use: deleteReminder)
    }

    func listComments(req: Request) async throws -> [TaskCommentResponse] {
        let (task, _) = try await requiredTask(req, permission: .view)
        let comments = try await TaskComment.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .with(\.$author)
            .sort(\.$createdAt, .ascending)
            .all()
        return try comments.map { try TaskCommentResponse(comment: $0, authorName: $0.author.name) }
    }

    func createComment(req: Request) async throws -> Response {
        try CreateTaskCommentRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskCommentRequest.self)
        let (task, _) = try await requiredTask(req, permission: .comment)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Comments cannot be empty.")
        }
        let user = try req.auth.require(User.self)
        let comment = TaskComment(
            taskID: try task.requireID(),
            authorID: try user.requireID(),
            body: body
        )
        try await comment.create(on: req.db)
        let board = try await task.$board.get(on: req.db)
        let actorID = try user.requireID()
        let followers = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .with(\.$user)
            .all()
        // Always include the commenter so self-comments notify their author.
        // Remove the actor from the follower list first to avoid duplicate emails.
        let recipients = [user] + followers.map(\.user).filter { $0.id != actorID }
        if let configuration = req.application.notificationConfiguration {
            for recipient in recipients {
                await NotificationService.enqueue(
                    try NotificationEvent.taskCommentAdded(
                        comment: comment,
                        task: task,
                        board: board,
                        actor: user,
                        recipient: recipient,
                        appURL: configuration.publicAppURL
                    ),
                    for: req
                )
            }
        }
        return try await TaskCommentResponse(comment: comment, authorName: user.name)
            .encodeResponse(status: .created, for: req)
    }

    func updateComment(req: Request) async throws -> TaskCommentResponse {
        try CreateTaskCommentRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskCommentRequest.self)
        let (task, access) = try await requiredTask(req, permission: .comment)
        let comment = try await requiredComment(req, taskID: task.requireID())
        try requireCommentOwner(comment, access: access, req: req)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Comments cannot be empty.")
        }
        comment.body = body
        try await comment.update(on: req.db)
        let author = try await comment.$author.get(on: req.db)
        return try TaskCommentResponse(comment: comment, authorName: author.name)
    }

    func deleteComment(req: Request) async throws -> HTTPStatus {
        let (task, access) = try await requiredTask(req, permission: .comment)
        let comment = try await requiredComment(req, taskID: task.requireID())
        try requireCommentOwner(comment, access: access, req: req)
        try await comment.delete(on: req.db)
        return .noContent
    }

    func listChecklist(req: Request) async throws -> [TaskChecklistItemResponse] {
        let (task, _) = try await requiredTask(req, permission: .view)
        let items = try await ChecklistItem.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .sort(\.$position, .ascending)
            .all()
        return try items.map(TaskChecklistItemResponse.init)
    }

    func createChecklistItem(req: Request) async throws -> Response {
        try CreateChecklistItemRequest.validate(content: req)
        let input = try req.content.decode(CreateChecklistItemRequest.self)
        let (task, _) = try await requiredTask(req, permission: .edit)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Checklist item titles cannot be empty.")
        }
        let taskID = try task.requireID()
        let count = try await ChecklistItem.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .count()
        let item = ChecklistItem(
            taskID: taskID,
            title: title,
            position: (count + 1) * 1_000
        )
        try await item.create(on: req.db)
        return try await TaskChecklistItemResponse(item: item)
            .encodeResponse(status: .created, for: req)
    }

    func updateChecklistItem(req: Request) async throws -> TaskChecklistItemResponse {
        let input = try req.content.decode(UpdateChecklistItemRequest.self)
        let (task, _) = try await requiredTask(req, permission: .edit)
        let item = try await requiredChecklistItem(req, taskID: task.requireID())
        if let title = input.title {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...200).contains(title.count) else {
                throw Abort(
                    .unprocessableEntity,
                    reason: "Use a checklist title between 1 and 200 characters."
                )
            }
            item.title = title
        }
        if let isCompleted = input.isCompleted {
            item.isCompleted = isCompleted
        }
        try await item.update(on: req.db)
        return try TaskChecklistItemResponse(item: item)
    }

    /// Reorders one checklist item and normalizes all positions in one transaction.
    /// A failed save rolls back the complete order change.
    func moveChecklistItem(req: Request) async throws -> TaskChecklistItemResponse {
        try MoveChecklistItemRequest.validate(content: req)
        let input = try req.content.decode(MoveChecklistItemRequest.self)
        let (task, _) = try await requiredTask(req, permission: .edit)
        let taskID = try task.requireID()
        let item = try await requiredChecklistItem(req, taskID: taskID)
        let itemID = try item.requireID()
        return try await req.db.transaction { database in
            var items = try await ChecklistItem.query(on: database)
                .filter(\.$task.$id == taskID)
                .filter(\.$id != itemID)
                .sort(\.$position, .ascending)
                .all()
            items.insert(item, at: min(input.targetIndex, items.count))
            for (index, current) in items.enumerated() {
                current.position = (index + 1) * 1_000
                try await current.update(on: database)
            }
            return try TaskChecklistItemResponse(item: item)
        }
    }

    func deleteChecklistItem(req: Request) async throws -> HTTPStatus {
        let (task, _) = try await requiredTask(req, permission: .edit)
        let item = try await requiredChecklistItem(req, taskID: task.requireID())
        try await item.delete(on: req.db)
        return .noContent
    }

    func listFollowers(req: Request) async throws -> [TaskFollowerResponse] {
        let (task, _) = try await requiredTask(req, permission: .view)
        let followers = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .with(\.$user)
            .sort(\.$createdAt, .ascending)
            .all()
        return try followers.map { try TaskFollowerResponse(follower: $0, user: $0.user) }
    }

    /// Following is idempotent. An existing record returns 200 and a new record
    /// returns 201, so retries do not create duplicates or report false failures.
    func follow(req: Request) async throws -> Response {
        let (task, _) = try await requiredTask(req, permission: .view)
        let taskID = try task.requireID()
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        if let follower = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .filter(\.$user.$id == userID)
            .first()
        {
            return try await TaskFollowerResponse(follower: follower, user: user)
                .encodeResponse(for: req)
        }
        let follower = TaskFollower(taskID: taskID, userID: userID)
        try await follower.create(on: req.db)
        return try await TaskFollowerResponse(follower: follower, user: user)
            .encodeResponse(status: .created, for: req)
    }

    func unfollow(req: Request) async throws -> HTTPStatus {
        let (task, _) = try await requiredTask(req, permission: .view)
        let userID = try req.auth.require(User.self).requireID()
        if let follower = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .filter(\.$user.$id == userID)
            .first()
        {
            try await follower.delete(on: req.db)
        }
        return .noContent
    }

    func listReminders(req: Request) async throws -> [TaskReminderResponse] {
        let (task, _) = try await requiredTask(req, permission: .view)
        let userID = try req.auth.require(User.self).requireID()
        let reminders = try await TaskReminder.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .filter(\.$user.$id == userID)
            .filter(\.$queuedAt == nil)
            .sort(\.$remindAt, .ascending)
            .all()
        return try reminders.map(TaskReminderResponse.init)
    }

    func createReminder(req: Request) async throws -> Response {
        guard req.application.notificationConfiguration != nil else {
            throw Abort(.serviceUnavailable, reason: "Email notifications are not configured.")
        }
        try CreateTaskReminderRequest.validate(content: req)
        let input = try req.content.decode(CreateTaskReminderRequest.self)
        let (task, _) = try await requiredTask(req, permission: .view)
        let taskID = try task.requireID()
        let userID = try req.auth.require(User.self).requireID()
        guard TimeZone(identifier: input.timeZone) != nil else {
            throw Abort(.unprocessableEntity, reason: "Choose a valid time zone.")
        }
        let now = Date()
        guard input.remindAt > now.addingTimeInterval(30) else {
            throw Abort(.unprocessableEntity, reason: "Choose a reminder time in the future.")
        }
        guard input.remindAt < now.addingTimeInterval(60 * 60 * 24 * 366 * 2) else {
            throw Abort(.unprocessableEntity, reason: "Choose a reminder within the next two years.")
        }
        let pendingCount = try await TaskReminder.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .filter(\.$user.$id == userID)
            .filter(\.$queuedAt == nil)
            .count()
        guard pendingCount < 3 else {
            throw Abort(.conflict, reason: "A task can have up to three pending reminders.")
        }
        let reminder = TaskReminder(
            taskID: taskID,
            userID: userID,
            remindAt: input.remindAt,
            timeZoneIdentifier: input.timeZone
        )
        do {
            try await reminder.create(on: req.db)
        } catch {
            throw Abort(.conflict, reason: "A reminder already exists at that time.")
        }
        return try await TaskReminderResponse(reminder: reminder)
            .encodeResponse(status: .created, for: req)
    }

    func deleteReminder(req: Request) async throws -> HTTPStatus {
        let (task, _) = try await requiredTask(req, permission: .view)
        let userID = try req.auth.require(User.self).requireID()
        guard
            let reminderID = req.parameters.get("reminderID", as: UUID.self),
            let reminder = try await TaskReminder.query(on: req.db)
                .filter(\.$id == reminderID)
                .filter(\.$task.$id == task.requireID())
                .filter(\.$user.$id == userID)
                .filter(\.$queuedAt == nil)
                .first()
        else {
            throw Abort(.notFound, reason: "The reminder does not exist.")
        }
        try await reminder.delete(on: req.db)
        return .noContent
    }

    private func requiredTask(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> (Task, BoardAccess) {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        let access = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
        return (task, access)
    }

    private func requiredComment(_ req: Request, taskID: UUID) async throws -> TaskComment {
        guard
            let commentID = req.parameters.get("commentID", as: UUID.self),
            let comment = try await TaskComment.query(on: req.db)
                .filter(\.$id == commentID)
                .filter(\.$task.$id == taskID)
                .first()
        else {
            throw Abort(.notFound, reason: "The comment does not exist.")
        }
        return comment
    }

    private func requiredChecklistItem(_ req: Request, taskID: UUID) async throws -> ChecklistItem {
        guard
            let itemID = req.parameters.get("itemID", as: UUID.self),
            let item = try await ChecklistItem.query(on: req.db)
                .filter(\.$id == itemID)
                .filter(\.$task.$id == taskID)
                .first()
        else {
            throw Abort(.notFound, reason: "The checklist item does not exist.")
        }
        return item
    }

    private func requireCommentOwner(
        _ comment: TaskComment,
        access: BoardAccess,
        req: Request
    ) throws {
        let userID = try req.auth.require(User.self).requireID()
        guard access.isOwner || access.role == .admin || comment.$author.id == userID else {
            throw Abort(.forbidden, reason: "You cannot change this comment.")
        }
    }
}
