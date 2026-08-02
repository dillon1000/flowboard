import Fluent
import Foundation
import Vapor

enum TapActionService {
    struct Definition: Sendable {
        let name: String
        let displayDescription: String?
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
            displayDescription: cleanDefinition.displayDescription,
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
        action.displayDescription = cleanDefinition.displayDescription
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

    /// Returns the board-defined form for a scanned tag without changing state.
    /// The raw bearer token stays in the POST body and is checked before board data is exposed.
    static func prepare(
        _ input: TapPreparationRequest,
        on database: any Database
    ) async throws -> TapPreparationResponse {
        guard TapTokenService.isWellFormed(input.token) else {
            throw Abort(.notFound, reason: "This Tap link is not valid.")
        }
        guard let action = try await TapAction.query(on: database)
            .filter(\.$tokenHash == TapTokenService.hash(input.token))
            .with(\.$board)
            .first()
        else {
            throw Abort(.notFound, reason: "This Tap link is not valid.")
        }
        try validateAvailability(action, at: Date())
        return TapPreparationResponse(
            actionName: action.name,
            actionDescription: action.displayDescription,
            kind: action.kind,
            task: try await taskForm(for: action, on: database)
        )
    }

    /// Executes an action without a user session. Token lifecycle checks, the
    /// scanner-entered task mutation, the use counter, and the audit record share one transaction.
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
                    actionDescription: existing.actionDescription,
                    message: existing.message
                )
            }

            let now = Date()
            try validateAvailability(action, at: now)
            if let lastUsedAt = action.lastUsedAt,
                now.timeIntervalSince(lastUsedAt) < Double(action.cooldownSeconds)
            {
                throw Abort(.tooManyRequests, reason: "This Tap action was just used. Try again shortly.")
            }

            let result = try await apply(action, taskInput: input.task, on: transaction)
            action.useCount += 1
            action.lastUsedAt = now
            try await action.update(on: transaction)
            try await TapExecution(
                actionID: actionID,
                taskID: result.taskID,
                requestID: input.requestID,
                actionName: action.name,
                actionDescription: action.displayDescription,
                message: result.message
            ).create(on: transaction)
            return TapExecutionResponse(
                actionName: action.name,
                actionDescription: action.displayDescription,
                message: result.message
            )
        }
    }

    private static func apply(
        _ action: TapAction,
        taskInput: TapTaskInput?,
        on database: any Database
    ) async throws -> (taskID: UUID, message: String) {
        let board = action.board
        let status = TaskStatus(rawValue: action.configuration.status)
        guard board.accepts(status: status) else {
            throw Abort(.unprocessableEntity, reason: "This Tap action uses a status that is no longer available.")
        }

        switch action.kind {
        case .createTask:
            let input = try required(taskInput, reason: "Complete the task details before you create it.")
            let title = try required(clean(input.title), reason: "Task title is required.")
            guard title.count <= 120 else {
                throw Abort(.unprocessableEntity, reason: "Task title must contain 120 characters or fewer.")
            }
            let description = clean(input.description)
            guard (description?.count ?? 0) <= 5_000 else {
                throw Abort(.unprocessableEntity, reason: "Task description must contain 5,000 characters or fewer.")
            }
            let status = TaskStatus(rawValue: try required(clean(input.status), reason: "Select a status."))
            let priority = TaskPriority(rawValue: try required(clean(input.priority), reason: "Select a severity."))
            guard board.accepts(status: status), board.accepts(priority: priority) else {
                throw Abort(.unprocessableEntity, reason: "Select a status and severity configured for this board.")
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
                description: description,
                status: status,
                priority: priority,
                position: (count + 1) * 1_000,
                labels: cleanLabels(input.labels),
                startAt: try date(from: input.startAt, field: "Start date"),
                dueAt: try date(from: input.dueAt, field: "Due date")
            )
            task.properties = try await properties(from: input.properties, for: board, on: database)
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
        let displayDescription = clean(definition.displayDescription)
        guard (displayDescription?.count ?? 0) <= 280 else {
            throw Abort(.unprocessableEntity, reason: "Tap description must contain 280 characters or fewer.")
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
                board.accepts(priority: priority)
            else {
                throw Abort(.unprocessableEntity, reason: "Select a default severity configured for this board.")
            }
            configuration = TapActionConfiguration(
                title: nil,
                description: nil,
                status: status.rawValue,
                priority: priority.rawValue,
                labels: []
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
            displayDescription: displayDescription,
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

    private static func validateAvailability(_ action: TapAction, at now: Date) throws {
        guard action.isEnabled else {
            throw Abort(.gone, reason: "This Tap action is disabled.")
        }
        if let expiresAt = action.expiresAt, expiresAt <= now {
            throw Abort(.gone, reason: "This Tap action has expired.")
        }
        if let maxUses = action.maxUses, action.useCount >= maxUses {
            throw Abort(.gone, reason: "This Tap action has reached its use limit.")
        }
    }

    private static func taskForm(
        for action: TapAction,
        on database: any Database
    ) async throws -> TapTaskForm? {
        guard action.kind == .createTask else { return nil }
        let board = action.board
        let boardID = try board.requireID()
        let members = try await BoardMember.query(on: database)
            .filter(\.$board.$id == boardID)
            .with(\.$user)
            .all()
        guard let owner = try await board.$owner.get(on: database) else {
            throw Abort(.notFound, reason: "The board owner does not exist.")
        }
        var people = [TapTaskOption(id: try owner.requireID().uuidString.lowercased(), name: owner.name)]
        let knownPeople = Set(people.map { $0.id })
        people += try members.compactMap { member in
            let id = try member.user.requireID().uuidString.lowercased()
            return knownPeople.contains(id) ? nil : TapTaskOption(id: id, name: member.user.name)
        }
        let properties = (board.propertyDefinitions ?? []).map { definition in
            TapTaskProperty(
                id: definition.id,
                name: definition.name,
                type: definition.type,
                options: definition.type == .person
                    ? people
                    : definition.options.map { TapTaskOption(id: $0.id, name: $0.name) }
            )
        }
        let status = board.accepts(status: TaskStatus(rawValue: action.configuration.status))
            ? action.configuration.status
            : board.taskStatuses.first?.id ?? TaskStatus.backlog.rawValue
        let priority = action.configuration.priority.flatMap { value in
            board.accepts(priority: TaskPriority(rawValue: value)) ? value : nil
        } ?? board.taskSeverities.first?.id ?? TaskPriority.medium.rawValue
        return TapTaskForm(
            status: status,
            priority: priority,
            statuses: board.taskStatuses.map { TapTaskOption(id: $0.id, name: $0.name) },
            priorities: board.taskSeverities.map { TapTaskOption(id: $0.id, name: $0.name) },
            properties: properties
        )
    }

    private static func properties(
        from input: [String: String]?,
        for board: Board,
        on database: any Database
    ) async throws -> [String: String] {
        let definitions = board.propertyDefinitions ?? []
        let rawValues = input ?? [:]
        let personIDs = Set(
            definitions.filter { $0.type == .person }.compactMap { definition in
                rawValues[definition.id].flatMap { UUID(uuidString: $0) }
            }
        )
        if !personIDs.isEmpty {
            let boardID = try board.requireID()
            let members = try await BoardMember.query(on: database)
                .filter(\.$board.$id == boardID)
                .all()
            let allowed = Set(members.map(\.$user.id))
                .union([board.$owner.id].compactMap { $0 })
            guard personIDs.isSubset(of: allowed) else {
                throw Abort(.unprocessableEntity, reason: "Select a person who belongs to this board.")
            }
        }
        return try definitions.reduce(into: [:]) { values, definition in
            guard let raw = clean(rawValues[definition.id]) else { return }
            guard let normalized = definition.normalizedValue(raw) else {
                throw Abort(.unprocessableEntity, reason: "Enter a valid value for \(definition.name).")
            }
            values[definition.id] = normalized
        }
    }

    private static func cleanLabels(_ labels: [String]?) -> [String] {
        var seen: Set<String> = []
        return Array((labels ?? []).compactMap { clean($0) }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(6))
    }

    private static func date(from value: String?, field: String) throws -> Date? {
        guard let value = clean(value) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard formatter.string(from: formatter.date(from: value) ?? .distantPast) == value else {
            throw Abort(.unprocessableEntity, reason: "Enter a valid \(field.lowercased()).")
        }
        return formatter.date(from: value)
    }

    private static func required<T>(_ value: T?, reason: String) throws -> T {
        guard let value else { throw Abort(.unprocessableEntity, reason: reason) }
        return value
    }
}
