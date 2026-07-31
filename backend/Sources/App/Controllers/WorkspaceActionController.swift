import Fluent
import Foundation
import Vapor

/// Owns the state-changing browser routes. Each action checks board permissions
/// before changing data and redirects to a stable Leaf page after success.
struct WorkspaceActionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("app", "boards", use: createBoard)
        routes.post("app", "boards", ":boardID", "update", use: updateBoard)
        routes.post("app", "boards", ":boardID", "archive", use: toggleBoardArchive)
        routes.post("app", "boards", ":boardID", "duplicate", use: duplicateBoard)
        routes.post("app", "boards", ":boardID", "delete", use: deleteBoard)
        routes.get("app", "boards", ":boardID", "export", use: exportBoard)
        routes.post("app", "boards", ":boardID", "import", use: importBoard)

        routes.post("app", "boards", ":boardID", "views", use: createView)
        routes.post("app", "boards", ":boardID", "views", ":viewID", "configure", use: configureView)
        routes.post("app", "boards", ":boardID", "views", ":viewID", "delete", use: deleteView)
        routes.post("app", "boards", ":boardID", "properties", use: createProperty)
        routes.post("app", "boards", ":boardID", "task-options", use: createTaskOption)
        routes.post("app", "boards", ":boardID", "members", use: addMember)
        routes.post("app", "boards", ":boardID", "members", ":memberID", "remove", use: removeMember)
        routes.post("app", "boards", ":boardID", "templates", use: createTemplate)
        routes.post("app", "boards", ":boardID", "templates", ":templateID", "use", use: useTemplate)
        routes.post("app", "boards", ":boardID", "templates", ":templateID", "default", use: setDefaultTemplate)
        routes.post("app", "boards", ":boardID", "templates", ":templateID", "delete", use: deleteTemplate)

        routes.post("app", "tasks", use: createTask)
        routes.post("app", "tasks", ":taskID", "update", use: updateTask)
        routes.post("app", "tasks", ":taskID", "status", use: changeTaskStatus)
        routes.post("app", "tasks", ":taskID", "properties", use: updateTaskProperties)
        routes.post("app", "tasks", ":taskID", "archive", use: toggleTaskArchive)
        routes.post("app", "tasks", ":taskID", "delete", use: deleteTask)
        routes.post("app", "tasks", ":taskID", "comments", use: createComment)
        routes.post("app", "comments", ":commentID", "delete", use: deleteComment)
        routes.post("app", "tasks", ":taskID", "follow", use: toggleFollow)
        routes.post("app", "tasks", ":taskID", "checklist", use: createChecklistItem)
        routes.post("app", "checklist", ":itemID", "toggle", use: toggleChecklistItem)
        routes.post("app", "tasks", ":taskID", "attachments", use: createAttachment)
        routes.get("app", "attachments", ":attachmentID", use: downloadAttachment)
        routes.get("app", "attachments", ":attachmentID", "preview", use: previewAttachment)
        routes.post("app", "attachments", ":attachmentID", "delete", use: deleteAttachment)

        routes.post("app", "settings", "profile", use: updateProfile)
    }
}
