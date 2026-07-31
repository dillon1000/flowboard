import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
    func createTask(req: Request) async throws -> Response {
        let input = try req.content.decode(CreateTaskForm.self)
        let userID = try req.auth.require(User.self).requireID()
        let access = try await BoardAccessService.require(
            boardID: input.boardID,
            userID: userID,
            permission: .edit,
            on: req.db
        )
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Task title is required.")
        }
        let status = TaskStatus(rawValue: input.status ?? TaskStatus.backlog.rawValue)
        let priority = TaskPriority(rawValue: input.priority ?? TaskPriority.medium.rawValue)
        guard access.board.accepts(status: status), access.board.accepts(priority: priority) else {
            throw Abort(.unprocessableEntity, reason: "Select a status and severity configured for this board.")
        }
        let count = try await Task.query(on: req.db)
            .filter(\.$board.$id == input.boardID)
            .filter(\.$statusValue == status.rawValue)
            .count()
        let task = Task(
            boardID: input.boardID,
            title: title,
            description: clean(input.description),
            status: status,
            priority: priority,
            position: (count + 1) * 1_000,
            labels: labels(input.labels),
            startAt: parseDate(input.startAt),
            dueAt: parseDate(input.dueAt),
            creatorID: userID
        )
        try await task.create(on: req.db)
        return req.redirect(to: safeReturn(input.returnTo, fallback: "/app/tasks/\(try task.requireID())"))
    }

    func updateTask(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(UpdateTaskForm.self)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = TaskStatus(rawValue: input.status)
        let priority = TaskPriority(rawValue: input.priority)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Task title, status, and severity are required.")
        }
        guard
            let board = try await Board.find(task.$board.id, on: req.db),
            board.accepts(status: status),
            board.accepts(priority: priority)
        else {
            throw Abort(.unprocessableEntity, reason: "Select a status and severity configured for this board.")
        }
        task.title = title
        task.description = clean(input.description)
        task.priority = priority
        task.labels = labels(input.labels)
        task.startAt = parseDate(input.startAt)
        task.dueAt = parseDate(input.dueAt)
        if task.status != status {
            let count = try await Task.query(on: req.db)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$statusValue == status.rawValue)
                .count()
            task.status = status
            task.position = (count + 1) * 1_000
        }
        if let assignee = clean(input.assigneeID).flatMap(UUID.init(uuidString:)) {
            let memberIDs = try await BoardAccessService.boardIDs(for: assignee, on: req.db)
            task.$assignee.id = memberIDs.contains(task.$board.id) ? assignee : nil
        } else {
            task.$assignee.id = nil
        }
        try await task.update(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    /// Accepts a status-only browser form, moves the task to the end of the
    /// selected column, and redirects to the task page. Permission and value
    /// failures occur before the task changes.
    func changeTaskStatus(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(ChangeTaskStatusForm.self)
        let status = TaskStatus(rawValue: input.status)
        guard
            let board = try await Board.find(task.$board.id, on: req.db),
            board.accepts(status: status)
        else {
            throw Abort(.unprocessableEntity, reason: "Select a status configured for this board.")
        }
        if task.status != status {
            let count = try await Task.query(on: req.db)
                .filter(\.$board.$id == task.$board.id)
                .filter(\.$statusValue == status.rawValue)
                .count()
            task.status = status
            task.position = (count + 1) * 1_000
            try await task.update(on: req.db)
        }
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func updateTaskProperties(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        guard let board = try await Board.find(task.$board.id, on: req.db) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        var values = task.properties ?? [:]
        for definition in board.propertyDefinitions ?? [] {
            let rawValue: String
            if definition.type == .multiSelect {
                let selected = definition.options.compactMap { option in
                    let key = "property-\(definition.id)-\(option.id)"
                    return (try? req.content.get(String.self, at: key)) == nil ? nil : option.id
                }
                let data = try JSONEncoder().encode(selected)
                rawValue = String(decoding: data, as: UTF8.self)
            } else {
                rawValue = (try? req.content.get(String.self, at: "property-\(definition.id)")) ?? ""
            }
            let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty || (definition.type == .multiSelect && cleaned == "[]") {
                values.removeValue(forKey: definition.id)
            } else if let normalized = definition.normalizedValue(cleaned) {
                values[definition.id] = normalized
            } else {
                throw Abort(.unprocessableEntity, reason: "Enter a valid value for \(definition.name).")
            }
        }
        task.properties = values
        try await task.update(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func toggleTaskArchive(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        task.isArchived.toggle()
        try await task.update(on: req.db)
        return req.redirect(
            to: task.isArchived
                ? "/app/boards/\(task.$board.id)"
                : "/app/tasks/\(try task.requireID())"
        )
    }

    func deleteTask(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let boardID = task.$board.id
        let taskID = try task.requireID()
        let attachments = try await TaskAttachment.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .all()
        try await deleteStoredAttachments(attachments, for: req)
        try await task.delete(on: req.db)
        removeLocalAttachmentDirectories(
            boardID: boardID,
            taskID: taskID,
            req: req
        )
        return req.redirect(to: "/app/boards/\(boardID)")
    }

    func createComment(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .comment)
        let input = try req.content.decode(CommentForm.self)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 4_000 else {
            throw Abort(.unprocessableEntity, reason: "Use a comment between 1 and 4,000 characters.")
        }
        try await TaskComment(
            taskID: task.requireID(),
            authorID: req.auth.require(User.self).requireID(),
            body: body
        ).create(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func deleteComment(req: Request) async throws -> Response {
        guard
            let commentID = req.parameters.get("commentID", as: UUID.self),
            let comment = try await TaskComment.find(commentID, on: req.db),
            let task = try await Task.find(comment.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The comment does not exist.")
        }
        let access = try await requireAccess(
            boardID: task.$board.id,
            permission: .comment,
            for: req
        )
        let userID = try req.auth.require(User.self).requireID()
        guard access.isOwner || access.role == .admin || comment.$author.id == userID else {
            throw Abort(.forbidden, reason: "You cannot delete this comment.")
        }
        try await comment.delete(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func toggleFollow(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .view)
        let taskID = try task.requireID()
        let userID = try req.auth.require(User.self).requireID()
        if let follower = try await TaskFollower.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .filter(\.$user.$id == userID)
            .first()
        {
            try await follower.delete(on: req.db)
        } else {
            try await TaskFollower(taskID: taskID, userID: userID).create(on: req.db)
        }
        return req.redirect(to: "/app/tasks/\(taskID)")
    }

    func createChecklistItem(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(ChecklistForm.self)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else {
            throw Abort(.unprocessableEntity, reason: "Use a checklist title between 1 and 200 characters.")
        }
        let taskID = try task.requireID()
        let count = try await ChecklistItem.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .count()
        try await ChecklistItem(taskID: taskID, title: title, position: count).create(on: req.db)
        return req.redirect(to: "/app/tasks/\(taskID)")
    }

    func toggleChecklistItem(req: Request) async throws -> Response {
        guard
            let itemID = req.parameters.get("itemID", as: UUID.self),
            let item = try await ChecklistItem.find(itemID, on: req.db),
            let task = try await Task.find(item.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The checklist item does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: .edit, for: req)
        item.isCompleted.toggle()
        try await item.update(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }
}
