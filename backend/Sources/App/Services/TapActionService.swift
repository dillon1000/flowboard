import Fluent
import Foundation
import Vapor

enum TapActionService {
    struct Definition: Sendable {
        let name: String
        let kind: TapActionKind
        let targetTaskID: UUID?
        let configuration: TapActionConfiguration
        let expiresAt: Date?
        let maxUses: Int?
        let cooldownSeconds: Int
    }

    /// Validates and stores one action, then returns the raw token for immediate
    /// tag writing. The raw value exists only in this return value.
    static func create(
        board: Board,
        definition: Definition,
        on database: any Database
    ) async throws -> (action: TapAction, rawToken: String) {
        let credential = TapTokenService.generate()
        let action = try await create(
            board: board,
            definition: definition,
            credential: credential,
            on: database
        )
        return (action, credential.raw)
    }

    /// Stores a caller-generated credential after its public URL is validated.
    /// This prevents an active action from existing when a tag URL is too long.
    static func create(
        board: Board,
        definition: Definition,
        credential: (raw: String, hash: String, visiblePrefix: String),
        on database: any Database
    ) async throws -> TapAction {
        let cleanDefinition = try await validated(definition, board: board, on: database)
        let action = TapAction(
            boardID: try board.requireID(),
            targetTaskID: cleanDefinition.targetTaskID,
            name: cleanDefinition.name,
            kind: cleanDefinition.kind,
            configuration: cleanDefinition.configuration,
            tokenHash: credential.hash,
            tokenPrefix: credential.visiblePrefix,
            expiresAt: cleanDefinition.expiresAt,
            maxUses: cleanDefinition.maxUses,
            cooldownSeconds: cleanDefinition.cooldownSeconds
        )
        try await action.create(on: database)
        return action
    }

    /// Changes the server-defined action without changing the physical tag URL.
    /// Existing copies of the URL immediately receive the new definition.
    static func update(
        _ action: TapAction,
        board: Board,
        definition: Definition,
        on database: any Database
    ) async throws {
        let cleanDefinition = try await validated(definition, board: board, on: database)
        action.name = cleanDefinition.name
        action.kind = cleanDefinition.kind
        action.$targetTask.id = cleanDefinition.targetTaskID
        action.configuration = cleanDefinition.configuration
        action.expiresAt = cleanDefinition.expiresAt
        action.maxUses = cleanDefinition.maxUses
        action.cooldownSeconds = cleanDefinition.cooldownSeconds
        try await action.update(on: database)
    }

    /// Replaces the bearer credential while retaining the action and its audit
    /// history. A new credential starts a new use-count lifecycle.
    static func rotate(
        _ action: TapAction,
        credential: (raw: String, hash: String, visiblePrefix: String),
        on database: any Database
    ) async throws {
        action.tokenHash = credential.hash
        action.tokenPrefix = credential.visiblePrefix
        action.useCount = 0
        action.lastUsedAt = nil
        try await action.update(on: database)
    }

    /// Executes the fixed action without a user session. Token lifecycle checks,
    /// the task mutation, the use counter, and the audit record share one transaction.
    static func execute(
        _ input: TapExecutionRequest,
        on database: any Database
    ) async throws -> TapExecutionResponse {
        guard TapTokenService.isWellFormed(input.token) else {
            throw Abort(.notFound, reason: "This Tap link is not valid.")
        }
        return try await database.transaction { transaction in
            guard let action = try await TapAction.query(on: transaction)
                .filter(\.$tokenHash == TapTokenService.hash(input.token))
                .with(\.$board)
                .first()
            else {
                throw Abort(.notFound, reason: "This Tap link is not valid.")
            }
            let actionID = try action.requireID()
            if let existing = try await TapExecution.query(on: transaction)
                .filter(\.$action.$id == actionID)
                .filter(\.$requestID == input.requestID)
                .first()
            {
                return TapExecutionResponse(
                    actionName: existing.actionName,
                    message: existing.message
                )
            }

            let now = Date()
            guard action.isEnabled else {
                throw Abort(.gone, reason: "This Tap action is disabled.")
            }
            if let expiresAt = action.expiresAt, expiresAt <= now {
                throw Abort(.gone, reason: "This Tap action has expired.")
            }
            if let maxUses = action.maxUses, action.useCount >= maxUses {
                throw Abort(.gone, reason: "This Tap action has reached its use limit.")
            }
            if let lastUsedAt = action.lastUsedAt,
                now.timeIntervalSince(lastUsedAt) < Double(action.cooldownSeconds)
            {
                throw Abort(.tooManyRequests, reason: "This Tap action was just used. Try again shortly.")
            }

            let result = try await apply(action, on: transaction)
            action.useCount += 1
            action.lastUsedAt = now
            try await action.update(on: transaction)
            try await TapExecution(
                actionID: actionID,
                taskID: result.taskID,
                requestID: input.requestID,
                actionName: action.name,
                message: result.message
            ).create(on: transaction)
            return TapExecutionResponse(actionName: action.name, message: result.message)
        }
    }

    private static func apply(
        _ action: TapAction,
        on database: any Database
    ) async throws -> (taskID: UUID, message: String) {
        let board = action.board
        let status = TaskStatus(rawValue: action.configuration.status)
        guard board.accepts(status: status) else {
            throw Abort(.unprocessableEntity, reason: "This Tap action uses a status that is no longer available.")
        }

        switch action.kind {
        case .createTask:
            let priority = TaskPriority(
                rawValue: action.configuration.priority ?? TaskPriority.medium.rawValue
            )
            guard
                let title = clean(action.configuration.title),
                board.accepts(priority: priority)
            else {
                throw Abort(.unprocessableEntity, reason: "This Tap action has an invalid task configuration.")
            }
            let boardID = try board.requireID()
            let count = try await Task.query(on: database)
                .filter(\.$board.$id == boardID)
                .filter(\.$statusValue == status.rawValue)
                .count()
            let task = Task(
                publicID: try await Task.uniquePublicID(on: database),
                boardID: boardID,
                title: title,
                description: clean(action.configuration.description),
                status: status,
                priority: priority,
                position: (count + 1) * 1_000,
                labels: Array(action.configuration.labels.prefix(6))
            )
            try await task.create(on: database)
            return (try task.requireID(), "Task created.")

        case .updateTask:
            guard
                let taskID = action.$targetTask.id,
                let task = try await Task.query(on: database)
                    .filter(\.$id == taskID)
                    .filter(\.$board.$id == board.requireID())
                    .first()
            else {
                throw Abort(.gone, reason: "The task assigned to this Tap action no longer exists.")
            }
            if task.status != status {
                let count = try await Task.query(on: database)
                    .filter(\.$board.$id == task.$board.id)
                    .filter(\.$statusValue == status.rawValue)
                    .count()
                task.status = status
                task.position = (count + 1) * 1_000
                try await task.update(on: database)
            }
            return (try task.requireID(), "Task updated.")
        }
    }

    private static func validated(
        _ definition: Definition,
        board: Board,
        on database: any Database
    ) async throws -> Definition {
        guard let name = clean(definition.name), name.count <= 80 else {
            throw Abort(.unprocessableEntity, reason: "Use a Tap action name between 1 and 80 characters.")
        }
        guard (0...300).contains(definition.cooldownSeconds) else {
            throw Abort(.unprocessableEntity, reason: "Cooldown must be between 0 and 300 seconds.")
        }
        if let expiresAt = definition.expiresAt, expiresAt <= Date() {
            throw Abort(.unprocessableEntity, reason: "Tap action expiry must be in the future.")
        }
        if let maxUses = definition.maxUses, maxUses < 1 {
            throw Abort(.unprocessableEntity, reason: "Tap action use limit must be at least 1.")
        }
        let status = TaskStatus(rawValue: definition.configuration.status)
        guard board.accepts(status: status) else {
            throw Abort(.unprocessableEntity, reason: "Select a status configured for this board.")
        }

        let configuration: TapActionConfiguration
        let targetTaskID: UUID?
        switch definition.kind {
        case .createTask:
            let priority = TaskPriority(
                rawValue: definition.configuration.priority ?? TaskPriority.medium.rawValue
            )
            guard
                let title = clean(definition.configuration.title),
                title.count <= 200,
                board.accepts(priority: priority)
            else {
                throw Abort(.unprocessableEntity, reason: "Enter a task title and severity configured for this board.")
            }
            let description = clean(definition.configuration.description)
            guard (description?.count ?? 0) <= 20_000 else {
                throw Abort(.unprocessableEntity, reason: "Task description must contain 20,000 characters or fewer.")
            }
            configuration = TapActionConfiguration(
                title: title,
                description: description,
                status: status.rawValue,
                priority: priority.rawValue,
                labels: Array(definition.configuration.labels.filter { !$0.isEmpty }.prefix(6))
            )
            targetTaskID = nil

        case .updateTask:
            guard
                let requestedTaskID = definition.targetTaskID,
                try await Task.query(on: database)
                    .filter(\.$id == requestedTaskID)
                    .filter(\.$board.$id == board.requireID())
                    .first() != nil
            else {
                throw Abort(.unprocessableEntity, reason: "Select a task from this board.")
            }
            configuration = TapActionConfiguration(
                title: nil,
                description: nil,
                status: status.rawValue,
                priority: nil,
                labels: []
            )
            targetTaskID = requestedTaskID
        }

        return Definition(
            name: name,
            kind: definition.kind,
            targetTaskID: targetTaskID,
            configuration: configuration,
            expiresAt: definition.expiresAt,
            maxUses: definition.maxUses,
            cooldownSeconds: definition.cooldownSeconds
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
