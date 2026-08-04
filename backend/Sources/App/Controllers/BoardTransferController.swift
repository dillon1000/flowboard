import Fluent
import Foundation
import Vapor

/// Copies and transfers board data without a browser form contract. Export files
/// use a versioned JSON document so incompatible formats fail before any write.
struct BoardTransferController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards", ":boardID")
        boards.post("duplicate", use: duplicate)
        boards.get("export", use: export)
        boards.post("import", use: importBoard)
    }

    /// Copies board-owned data in one transaction. Membership is excluded so
    /// the duplicate starts as a private board for the user who made the copy.
    func duplicate(req: Request) async throws -> BoardResponse {
        let access = try await requiredBoard(req, permission: .view)
        let userID = try req.auth.require(User.self).requireID()
        let sourceID = try access.board.requireID()
        let views = try await BoardView.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .sort(\.$position, .ascending)
            .all()
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .all()
        let templates = try await TaskTemplate.query(on: req.db)
            .filter(\.$board.$id == sourceID)
            .all()
        let name = String("\(access.board.name) copy".prefix(80))
        let slug = try await uniqueSlug(slugify(name), on: req.db)

        let copy = try await req.db.transaction { database in
            let board = Board(
                name: name,
                slug: slug,
                description: access.board.description,
                ownerID: userID
            )
            board.propertyDefinitions = access.board.propertyDefinitions
            board.statusDefinitions = access.board.taskStatuses
            board.severityDefinitions = access.board.taskSeverities
            try await board.create(on: database)
            let boardID = try board.requireID()

            for view in views {
                try await BoardView(
                    boardID: boardID,
                    name: view.name,
                    type: view.type,
                    position: view.position,
                    configuration: view.configuration
                ).create(on: database)
            }
            for source in tasks {
                let task = Task(
                    publicID: try await Task.uniquePublicID(on: database),
                    boardID: boardID,
                    title: source.title,
                    description: source.description,
                    status: source.status,
                    priority: source.priority,
                    position: source.position,
                    labels: source.labels,
                    startAt: source.startAt,
                    dueAt: source.dueAt,
                    creatorID: userID
                )
                task.properties = source.properties
                try await task.create(on: database)
            }
            for source in templates {
                try await TaskTemplate(
                    boardID: boardID,
                    name: source.name,
                    title: source.title,
                    description: source.description,
                    status: source.status,
                    priority: source.priority,
                    labels: source.labels,
                    isDefault: source.isDefault
                ).create(on: database)
            }
            return board
        }
        return try BoardResponse(board: copy)
    }

    func export(req: Request) async throws -> Response {
        let access = try await requiredBoard(req, permission: .view)
        let boardID = try access.board.requireID()
        let tasks = try await Task.query(on: req.db).filter(\.$board.$id == boardID).all()
        let views = try await BoardView.query(on: req.db).filter(\.$board.$id == boardID).all()
        let templates = try await TaskTemplate.query(on: req.db).filter(\.$board.$id == boardID).all()
        let payload = BoardExportDocument(
            version: 1,
            name: access.board.name,
            description: access.board.description,
            propertyDefinitions: access.board.propertyDefinitions ?? [],
            statusDefinitions: access.board.taskStatuses,
            severityDefinitions: access.board.taskSeverities,
            views: views.map {
                .init(name: $0.name, type: $0.type, position: $0.position, configuration: $0.configuration)
            },
            tasks: tasks.map {
                .init(
                    title: $0.title,
                    description: $0.description,
                    status: $0.status,
                    priority: $0.priority,
                    position: $0.position,
                    labels: $0.labels,
                    startAt: $0.startAt,
                    dueAt: $0.dueAt,
                    properties: $0.properties
                )
            },
            templates: templates.map {
                .init(
                    name: $0.name,
                    title: $0.title,
                    description: $0.description,
                    status: $0.status,
                    priority: $0.priority,
                    labels: $0.labels,
                    isDefault: $0.isDefault
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let response = Response(status: .ok, body: .init(data: try encoder.encode(payload)))
        response.headers.contentType = .json
        response.headers.contentDisposition = .init(.attachment, filename: "\(access.board.slug).json")
        return response
    }

    func importBoard(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req, permission: .admin)
        let input = try req.content.decode(BoardImportRequest.self)
        guard input.file.data.readableBytes <= 2_000_000 else {
            throw Abort(.payloadTooLarge, reason: "Board imports must be 2 MB or smaller.")
        }
        guard let data = input.file.data.getData(
            at: input.file.data.readerIndex,
            length: input.file.data.readableBytes
        ) else {
            throw Abort(.badRequest, reason: "The import file could not be read.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BoardExportDocument.self, from: data)
        guard payload.version == 1, payload.tasks.count <= 5_000 else {
            throw Abort(.unprocessableEntity, reason: "This board export is not supported.")
        }

        let importedStatuses = payload.statusDefinitions ?? BoardTaskOption.defaultStatuses
        let importedSeverities = payload.severityDefinitions ?? BoardTaskOption.defaultSeverities
        let statuses = merge(current: access.board.taskStatuses, imported: importedStatuses)
        let severities = merge(current: access.board.taskSeverities, imported: importedSeverities)
        guard
            statuses.count <= 12,
            severities.count <= 12,
            payload.tasks.allSatisfy({ task in
                importedStatuses.contains { $0.id == task.status.rawValue }
                    && importedSeverities.contains { $0.id == task.priority.rawValue }
            })
        else {
            throw Abort(.unprocessableEntity, reason: "The import contains invalid workflow values.")
        }

        let boardID = try access.board.requireID()
        let userID = try req.auth.require(User.self).requireID()
        try await req.db.transaction { database in
            access.board.statusDefinitions = statuses
            access.board.severityDefinitions = severities
            try await access.board.update(on: database)
            for source in payload.tasks {
                let task = Task(
                    publicID: try await Task.uniquePublicID(on: database),
                    boardID: boardID,
                    title: String(source.title.prefix(120)),
                    description: source.description,
                    status: source.status,
                    priority: source.priority,
                    position: source.position,
                    labels: Array(source.labels.prefix(6)),
                    startAt: source.startAt,
                    dueAt: source.dueAt,
                    creatorID: userID
                )
                task.properties = source.properties
                try await task.create(on: database)
            }
        }
        return .noContent
    }

    private func requiredBoard(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
    }

    private func uniqueSlug(_ requested: String, on database: any Database) async throws -> String {
        guard try await Board.query(on: database).filter(\.$slug == requested).first() != nil else {
            return requested
        }
        return "\(String(requested.prefix(39)))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func slugify(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "board" : normalized).prefix(48))
    }

    private func merge(
        current: [BoardTaskOption],
        imported: [BoardTaskOption]
    ) -> [BoardTaskOption] {
        imported.reduce(into: current) { result, option in
            if !result.contains(where: { $0.id == option.id }) {
                result.append(option)
            }
        }
    }
}

private struct BoardImportRequest: Content {
    let file: File
}

private struct BoardExportDocument: Codable {
    let version: Int
    let name: String
    let description: String?
    let propertyDefinitions: [BoardPropertyDefinition]
    let statusDefinitions: [BoardTaskOption]?
    let severityDefinitions: [BoardTaskOption]?
    let views: [ExportedBoardView]
    let tasks: [ExportedTask]
    let templates: [ExportedTemplate]
}

private struct ExportedBoardView: Codable {
    let name: String
    let type: BoardViewType
    let position: Int
    let configuration: BoardViewConfiguration?
}

private struct ExportedTask: Codable {
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

private struct ExportedTemplate: Codable {
    let name: String
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: TaskPriority
    let labels: [String]
    let isDefault: Bool
}
