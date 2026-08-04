import Fluent
import Foundation
import Vapor

enum TapActionKind: String, Codable, CaseIterable, Content, Sendable {
    case createTask = "create_task"
    case updateTask = "update_task"
}

/// Contains the workflow values that a bearer token can apply. The target task
/// is a relationship on `TapAction`, so task deletion cannot leave a stale UUID in JSON.
struct TapActionConfiguration: Codable, Sendable {
    let status: String
    let priority: String?
}

/// Defines one narrowly scoped action that a person can run without signing in.
/// Only the token digest is stored because possession of the raw token grants access.
final class TapAction: Model, @unchecked Sendable {
    static let schema = "tap_actions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @OptionalParent(key: "target_task_id")
    var targetTask: Task?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "display_description")
    var displayDescription: String?

    @Field(key: "kind")
    var kindValue: String

    @Field(key: "configuration")
    var configuration: TapActionConfiguration

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "token_prefix")
    var tokenPrefix: String

    @Field(key: "is_enabled")
    var isEnabled: Bool

    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    @OptionalField(key: "max_uses")
    var maxUses: Int?

    @Field(key: "use_count")
    var useCount: Int

    /// This server-owned interval rejects immediate duplicate scans while still
    /// allowing the same physical tag to create a new result on a later tap.
    @Field(key: "cooldown_seconds")
    var cooldownSeconds: Int

    @OptionalField(key: "last_used_at")
    var lastUsedAt: Date?

    @Children(for: \.$action)
    var executions: [TapExecution]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    var kind: TapActionKind {
        get { TapActionKind(rawValue: kindValue) ?? .createTask }
        set { kindValue = newValue.rawValue }
    }

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        targetTaskID: UUID? = nil,
        name: String,
        displayDescription: String? = nil,
        kind: TapActionKind,
        configuration: TapActionConfiguration,
        tokenHash: String,
        tokenPrefix: String,
        isEnabled: Bool = true,
        expiresAt: Date? = nil,
        maxUses: Int? = nil,
        useCount: Int = 0,
        cooldownSeconds: Int = 3
    ) {
        self.id = id
        self.$board.id = boardID
        self.$targetTask.id = targetTaskID
        self.name = name
        self.displayDescription = displayDescription
        self.kindValue = kind.rawValue
        self.configuration = configuration
        self.tokenHash = tokenHash
        self.tokenPrefix = tokenPrefix
        self.isEnabled = isEnabled
        self.expiresAt = expiresAt
        self.maxUses = maxUses
        self.useCount = useCount
        self.cooldownSeconds = cooldownSeconds
    }
}

/// Records one completed execution. `requestID` makes a retried browser request
/// return its first result without applying the task change a second time.
final class TapExecution: Model, @unchecked Sendable {
    static let schema = "tap_executions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "action_id")
    var action: TapAction

    @OptionalParent(key: "task_id")
    var task: Task?

    @Field(key: "request_id")
    var requestID: UUID

    @Field(key: "action_name")
    var actionName: String

    @OptionalField(key: "action_description")
    var actionDescription: String?

    @Field(key: "message")
    var message: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        actionID: UUID,
        taskID: UUID?,
        requestID: UUID,
        actionName: String,
        actionDescription: String?,
        message: String
    ) {
        self.id = id
        self.$action.id = actionID
        self.$task.id = taskID
        self.requestID = requestID
        self.actionName = actionName
        self.actionDescription = actionDescription
        self.message = message
    }
}

struct TapExecutionRequest: Content {
    let token: String
    let requestID: UUID
    let task: TapTaskInput?

    init(token: String, requestID: UUID, task: TapTaskInput? = nil) {
        self.token = token
        self.requestID = requestID
        self.task = task
    }
}

/// Holds task values entered on the scanner's phone. The bearer token still
/// scopes these values to one board and one allowed Tap action.
struct TapTaskInput: Content {
    let title: String?
    let description: String?
    let status: String?
    let priority: String?
    let labels: [String]?
    let startAt: String?
    let dueAt: String?
    let properties: [String: String]?
}

struct TapPreparationRequest: Content {
    let token: String
}

/// Provides the safe, board-defined input choices after a tag has been read.
/// The token is sent in the request body, so it never enters a URL or referrer.
struct TapPreparationResponse: Content {
    let actionName: String
    let actionDescription: String?
    let kind: TapActionKind
    let task: TapTaskForm?
}

struct TapTaskForm: Content {
    let status: String
    let priority: String
    let statuses: [TapTaskOption]
    let priorities: [TapTaskOption]
    let properties: [TapTaskProperty]
}

struct TapTaskOption: Content {
    let id: String
    let name: String
}

struct TapTaskProperty: Content {
    let id: String
    let name: String
    let type: BoardPropertyType
    let options: [TapTaskOption]
}

struct TapExecutionResponse: Content {
    let actionName: String
    let actionDescription: String?
    let message: String
}
