import Foundation
import Vapor

enum MCPJSONValue: Codable, Equatable, Sendable {
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: MCPJSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: MCPJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case let .integer(value): value
        case let .number(value) where value.rounded() == value: Int(value)
        default: nil
        }
    }

    static func encoded<Value: Encodable>(_ value: Value) throws -> MCPJSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(MCPJSONValue.self, from: encoder.encode(value))
    }
}

struct MCPRequest: Content {
    let jsonrpc: String
    let id: MCPJSONValue?
    let method: String
    let params: MCPJSONValue?
}

struct MCPResponse: Content {
    let jsonrpc: String
    let id: MCPJSONValue
    let result: MCPJSONValue?
    let error: MCPError?

    init(id: MCPJSONValue, result: MCPJSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: MCPJSONValue, error: MCPError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct MCPError: Codable, Sendable {
    let code: Int
    let message: String
    let data: MCPJSONValue?

    init(code: Int, message: String, data: MCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

struct MCPToolDefinition: Codable, Sendable {
    let name: String
    let title: String
    let description: String
    let inputSchema: MCPJSONValue
    let annotations: MCPToolAnnotations
}

struct MCPToolAnnotations: Codable, Sendable {
    let readOnlyHint: Bool
    let destructiveHint: Bool
    let idempotentHint: Bool
    let openWorldHint: Bool
}

struct MCPResource: Codable, Sendable {
    let uri: String
    let name: String
    let title: String
    let description: String
    let mimeType: String
}

struct MCPResourceTemplate: Codable, Sendable {
    let uriTemplate: String
    let name: String
    let title: String
    let description: String
    let mimeType: String
}

struct MCPTextContent: Codable, Sendable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

struct MCPToolResult: Codable, Sendable {
    let content: [MCPTextContent]
    let structuredContent: MCPJSONValue
    let isError: Bool
}

struct MCPResourceContents: Codable, Sendable {
    let uri: String
    let mimeType: String
    let text: String

    init(uri: String, text: String) {
        self.uri = uri
        self.mimeType = "application/json"
        self.text = text
    }
}

struct MCPBoardSummary: Codable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let isArchived: Bool
    let taskCount: Int
    let completedCount: Int
    let canvasCourse: MCPCanvasCourseSummary?
    let createdAt: Date?
    let updatedAt: Date?
}

struct MCPBoardDetail: Codable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let isArchived: Bool
    let propertyDefinitions: [BoardPropertyDefinition]
    let statusDefinitions: [BoardTaskOption]
    let severityDefinitions: [BoardTaskOption]
    let canvasCourse: MCPCanvasCourseSummary?
    let tasks: [MCPTaskDetail]
    let createdAt: Date?
    let updatedAt: Date?
}

struct MCPTaskDetail: Codable, Sendable {
    let id: UUID
    let publicID: String
    let boardID: UUID
    let boardName: String
    let title: String
    let description: String?
    let status: String
    let severity: String
    let position: Int
    let labels: [String]
    let startAt: Date?
    let dueAt: Date?
    let dueTime: String?
    let estimatedMinutes: Int?
    let gradeEarned: Double?
    let gradePossible: Double?
    let assigneeID: UUID?
    let creatorID: UUID?
    let properties: [String: String]
    let isArchived: Bool
    let browserPath: String
    let canvasAssignment: MCPCanvasAssignmentSummary?
    let createdAt: Date?
    let updatedAt: Date?
}

struct MCPCanvasConnectionSummary: Codable, Sendable {
    let id: UUID
    let canvasOrigin: String
    let lastSnapshotID: String?
    let lastCapturedAt: Date?
    let lastSuccessfulSyncAt: Date?
    let lastErrorSummary: String?
    let courses: [MCPCanvasCourseDetail]
}

struct MCPCanvasCourseSummary: Codable, Sendable {
    let remoteCourseID: String
    let canvasCourseURL: String
    let courseCode: String?
    let termName: String?
    let currentScore: Double?
    let currentGrade: String?
    let syncArchived: Bool
}

struct MCPCanvasCourseDetail: Codable, Sendable {
    let id: UUID
    let boardID: UUID
    let boardName: String
    let remoteCourseID: String
    let canvasCourseURL: String
    let courseCode: String?
    let termName: String?
    let currentScore: Double?
    let currentGrade: String?
    let syncArchived: Bool
    let assignments: [MCPTaskDetail]
}

struct MCPCanvasAssignmentSummary: Codable, Sendable {
    let remoteAssignmentID: String
    let canvasAssignmentURL: String
    let submissionState: String?
    let gradeLabel: String?
    let submittedAt: Date?
    let isLate: Bool
    let isMissing: Bool
    let isExcused: Bool
    let redoRequested: Bool
    let syncArchived: Bool
    let canvasControlsCompletion: Bool
}
