import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
    func exportBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .view)
        let boardID = try access.board.requireID()
        let tasks = try await Task.query(on: req.db).filter(\.$board.$id == boardID).all()
        let views = try await BoardView.query(on: req.db).filter(\.$board.$id == boardID).all()
        let templates = try await TaskTemplate.query(on: req.db).filter(\.$board.$id == boardID).all()
        let payload = BoardExport(
            version: 1,
            name: access.board.name,
            description: access.board.description,
            propertyDefinitions: access.board.propertyDefinitions ?? [],
            views: views.map {
                ExportView(name: $0.name, type: $0.type, position: $0.position, configuration: $0.configuration)
            },
            tasks: tasks.map {
                ExportTask(
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
                ExportTemplate(
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
        let data = try encoder.encode(payload)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        response.headers.contentDisposition = .init(
            .attachment,
            filename: "\(access.board.slug).json"
        )
        return response
    }

    func importBoard(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let userID = try req.auth.require(User.self).requireID()
        let input = try req.content.decode(ImportForm.self)
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
        let payload = try decoder.decode(BoardExport.self, from: data)
        guard payload.version == 1, payload.tasks.count <= 5_000 else {
            throw Abort(.unprocessableEntity, reason: "This board export is not supported.")
        }
        let boardID = try access.board.requireID()
        try await req.db.transaction { database in
            for exported in payload.tasks {
                let task = Task(
                    boardID: boardID,
                    title: String(exported.title.prefix(120)),
                    description: exported.description,
                    status: exported.status,
                    priority: exported.priority,
                    position: exported.position,
                    labels: Array(exported.labels.prefix(6)),
                    startAt: exported.startAt,
                    dueAt: exported.dueAt,
                    creatorID: userID
                )
                task.properties = exported.properties
                try await task.create(on: database)
            }
        }
        return req.redirect(to: "/app/boards/\(boardID)")
    }
}
