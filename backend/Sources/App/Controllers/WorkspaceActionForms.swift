import Fluent
import Foundation
import Vapor

struct CreateBoardForm: Content {
    let name: String
    let description: String?
}

struct UpdateBoardForm: Content {
    let name: String
    let description: String?
}

struct CreateAPIKeyForm: Content {
    let name: String
}

struct CreateViewForm: Content {
    let name: String
    let type: String
}

struct ConfigureViewForm: Content {
    let groupBy: String?
    let filterField: String?
    let filterValue: String?
    let sortField: String?
    let sortDirection: String?
}

struct CreatePropertyForm: Content {
    let name: String
    let type: String
    let options: String?
}

struct CreateTaskOptionForm: Content {
    let kind: String
    let name: String
    let color: String
    let isCompleted: String?
}

struct AddMemberForm: Content {
    let email: String
    let role: String
}

struct CreateTemplateForm: Content {
    let name: String
    let title: String
}

struct TapActionForm: Content {
    let name: String
    let kind: String
    let targetTaskID: String?
    let title: String?
    let description: String?
    let status: String
    let priority: String?
    let labels: String?
    let expiresAt: String?
    let maxUses: String?
    let cooldownSeconds: String?
}

struct CreateTaskForm: Content {
    let boardID: UUID
    let title: String
    let description: String?
    let status: String?
    let priority: String?
    let labels: String?
    let startAt: String?
    let dueAt: String?
    let returnTo: String?
}

struct UpdateTaskForm: Content {
    let title: String
    let description: String?
    let status: String
    let priority: String
    let labels: String?
    let startAt: String?
    let dueAt: String?
    let assigneeID: String?
}

struct ChangeTaskStatusForm: Content {
    let status: String
}

struct CommentForm: Content {
    let body: String
}

struct ChecklistForm: Content {
    let title: String
}

struct AttachmentForm: Content {
    let file: File
}

struct ImportForm: Content {
    let file: File
}

struct BoardExport: Codable {
    let version: Int
    let name: String
    let description: String?
    let propertyDefinitions: [BoardPropertyDefinition]
    let statusDefinitions: [BoardTaskOption]?
    let severityDefinitions: [BoardTaskOption]?
    let views: [ExportView]
    let tasks: [ExportTask]
    let templates: [ExportTemplate]
}

struct ExportView: Codable {
    let name: String
    let type: BoardViewType
    let position: Int
    let configuration: BoardViewConfiguration?
}

struct ExportTask: Codable {
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let position: Int
    let labels: [String]
    let startAt: Date?
    let dueAt: Date?
    let properties: [String: String]?
}

struct ExportTemplate: Codable {
    let name: String
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let labels: [String]
    let isDefault: Bool
}
