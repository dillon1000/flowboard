import Fluent
import Foundation
import Vapor

/// Adds board-owned fields and workflow values through JSON endpoints. Each
/// mutation validates the complete value before it changes the board document.
struct BoardConfigurationController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards", ":boardID")
        boards.post("properties", use: createProperty)
        boards.patch("properties", ":propertyID", use: updateProperty)
        boards.delete("properties", ":propertyID", use: deleteProperty)
        boards.post("task-options", use: createTaskOption)
        boards.patch("task-options", ":optionID", use: updateTaskOption)
    }

    func createProperty(req: Request) async throws -> BoardResponse {
        let access = try await requiredBoard(req)
        let input = try req.content.decode(CreatePropertyRequest.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a field name between 1 and 60 characters.")
        }

        let optionNames = input.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if input.type.usesOptions {
            guard
                (1...20).contains(optionNames.count),
                optionNames.allSatisfy({ (1...40).contains($0.count) }),
                Set(optionNames.map { $0.lowercased() }).count == optionNames.count
            else {
                throw Abort(
                    .unprocessableEntity,
                    reason: "Add 1 to 20 unique options, each no longer than 40 characters."
                )
            }
        }

        let palette = BoardTaskOptionColor.presetPalette
        var usedIDs: Set<String> = []
        let options: [BoardPropertyOption] = if input.type.usesOptions {
            optionNames.enumerated().map { index, optionName in
                var optionID = slugify(optionName)
                var suffix = 2
                while usedIDs.contains(optionID) {
                    optionID = "\(String(slugify(optionName).prefix(28)))-\(suffix)"
                    suffix += 1
                }
                usedIDs.insert(optionID)
                return BoardPropertyOption(
                    id: optionID,
                    name: optionName,
                    color: palette[index % palette.count].rawValue
                )
            }
        } else {
            []
        }
        access.board.propertyDefinitions = (access.board.propertyDefinitions ?? []) + [
            BoardPropertyDefinition(
                id: UUID().uuidString.lowercased(),
                name: name,
                type: input.type,
                options: options
            ),
        ]
        try await access.board.update(on: req.db)
        return try BoardResponse(board: access.board)
    }

    func updateProperty(req: Request) async throws -> BoardResponse {
        let access = try await requiredBoard(req)
        let input = try req.content.decode(UpdatePropertyRequest.self)
        let propertyID = try req.parameters.require("propertyID")
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a field name between 1 and 60 characters.")
        }
        var definitions = access.board.propertyDefinitions ?? []
        guard let index = definitions.firstIndex(where: { $0.id == propertyID }) else {
            throw Abort(.notFound, reason: "The custom field does not exist on this course.")
        }
        guard !definitions.enumerated().contains(where: { definitionIndex, definition in
            definitionIndex != index && definition.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw Abort(.conflict, reason: "That custom field name already exists on this course.")
        }
        let current = definitions[index]
        definitions[index] = BoardPropertyDefinition(
            id: current.id,
            name: name,
            type: current.type,
            options: current.options
        )
        access.board.propertyDefinitions = definitions
        try await access.board.update(on: req.db)
        return try BoardResponse(board: access.board)
    }

    /// Removes the definition, saved task values, and view rules that refer to
    /// the field. The transaction prevents partially deleted course metadata.
    func deleteProperty(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req)
        let propertyID = try req.parameters.require("propertyID")
        let definitions = access.board.propertyDefinitions ?? []
        guard definitions.contains(where: { $0.id == propertyID }) else {
            throw Abort(.notFound, reason: "The custom field does not exist on this course.")
        }
        let boardID = try access.board.requireID()
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .all()
        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .all()
        try await req.db.transaction { database in
            access.board.propertyDefinitions = definitions.filter { $0.id != propertyID }
            try await access.board.update(on: database)

            for task in tasks where task.properties?[propertyID] != nil {
                task.properties?.removeValue(forKey: propertyID)
                try await task.update(on: database)
            }

            for view in views {
                guard let configuration = view.configuration else { continue }
                let filters = configuration.filters.filter { $0.field != propertyID }
                let sorts = configuration.sorts.filter { $0.field != propertyID }
                guard filters.count != configuration.filters.count || sorts.count != configuration.sorts.count else {
                    continue
                }
                view.configuration = BoardViewConfiguration(
                    groupBy: configuration.groupBy,
                    filters: filters,
                    sorts: sorts
                )
                try await view.update(on: database)
            }
        }
        return .noContent
    }

    func createTaskOption(req: Request) async throws -> BoardResponse {
        let access = try await requiredBoard(req)
        let input = try req.content.decode(TaskOptionRequest.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a workflow name between 1 and 40 characters.")
        }

        let isStatus = input.kind == .status
        var options = isStatus ? access.board.taskStatuses : access.board.taskSeverities
        guard options.count < 12 else {
            throw Abort(.unprocessableEntity, reason: "A board can have up to 12 values of each type.")
        }
        guard !options.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw Abort(.conflict, reason: "That workflow name already exists on this board.")
        }

        let baseID = slugify(name)
        var optionID = baseID
        var suffix = 2
        while options.contains(where: { $0.id == optionID }) {
            optionID = "\(String(baseID.prefix(28)))-\(suffix)"
            suffix += 1
        }
        options.append(
            BoardTaskOption(
                id: optionID,
                name: name,
                color: input.color,
                isCompleted: isStatus && input.isCompleted
            )
        )
        if isStatus {
            access.board.statusDefinitions = options
        } else {
            access.board.severityDefinitions = options
        }
        try await access.board.update(on: req.db)
        return try BoardResponse(board: access.board)
    }

    /// Updates the presentation and completion behavior of one workflow value.
    /// The option ID remains stable because tasks store it as their status or severity.
    func updateTaskOption(req: Request) async throws -> BoardResponse {
        let access = try await requiredBoard(req)
        let input = try req.content.decode(TaskOptionRequest.self)
        let optionID = try req.parameters.require("optionID")
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a workflow name between 1 and 40 characters.")
        }

        let isStatus = input.kind == .status
        var options = isStatus ? access.board.taskStatuses : access.board.taskSeverities
        guard let index = options.firstIndex(where: { $0.id == optionID }) else {
            throw Abort(.notFound, reason: "The workflow value does not exist on this board.")
        }
        guard !options.enumerated().contains(where: { optionIndex, option in
            optionIndex != index && option.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw Abort(.conflict, reason: "That workflow name already exists on this board.")
        }

        options[index] = BoardTaskOption(
            id: optionID,
            name: name,
            color: input.color,
            isCompleted: isStatus && input.isCompleted
        )
        if isStatus {
            access.board.statusDefinitions = options
        } else {
            access.board.severityDefinitions = options
        }
        try await access.board.update(on: req.db)
        return try BoardResponse(board: access.board)
    }

    private func requiredBoard(_ req: Request) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: .admin,
            on: req.db
        )
    }

    private func slugify(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "option" : normalized).prefix(32))
    }
}

private struct CreatePropertyRequest: Content {
    let name: String
    let type: BoardPropertyType
    let options: [String]
}

private struct UpdatePropertyRequest: Content {
    let name: String
}

private struct TaskOptionRequest: Content {
    enum Kind: String, Codable {
        case status
        case severity
    }

    let kind: Kind
    let name: String
    let color: BoardTaskOptionColor
    let isCompleted: Bool
}
