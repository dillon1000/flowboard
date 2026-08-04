import Fluent
import Foundation
import Vapor

/// Serves private task attachments through authenticated API routes. Bucket
/// credentials and object keys never leave the application process.
struct AttachmentController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("tasks", ":taskID", "attachments", use: create)
        routes.get("attachments", ":attachmentID", use: download)
        routes.get("attachments", ":attachmentID", "preview", use: preview)
        routes.delete("attachments", ":attachmentID", use: delete)
    }

    func create(req: Request) async throws -> Response {
        let task = try await requiredTask(req, permission: .edit)
        let input = try req.content.decode(AttachmentUploadRequest.self)
        guard input.file.data.readableBytes <= 10_000_000 else {
            throw Abort(.payloadTooLarge, reason: "Attachments must be 10 MB or smaller.")
        }
        let taskID = try task.requireID()
        let fileExtension = input.file.extension?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let generatedName = UUID().uuidString + (fileExtension.map { ".\($0)" } ?? "")
        let storageName = AttachmentStorage.objectKey(
            boardID: task.$board.id,
            taskID: taskID,
            storageName: generatedName
        )
        let contentType = input.file.contentType?.serialize() ?? "application/octet-stream"
        try await AttachmentStorageService.store(
            input.file.data,
            key: storageName,
            contentType: contentType,
            for: req
        )

        let attachment = TaskAttachment(
            taskID: taskID,
            uploadedByID: try req.auth.require(User.self).requireID(),
            fileName: safeFileName(input.file.filename),
            storageName: storageName,
            contentType: contentType,
            byteCount: input.file.data.readableBytes
        )
        do {
            try await attachment.create(on: req.db)
        } catch {
            try? await AttachmentStorageService.delete(key: storageName, for: req)
            throw error
        }
        return try await AttachmentResponse(attachment: attachment)
            .encodeResponse(status: .created, for: req)
    }

    func download(req: Request) async throws -> Response {
        let (attachment, task) = try await requiredAttachment(req, permission: .view)
        let response = try await AttachmentStorageService.response(
            for: attachment,
            task: task,
            req: req
        )
        response.headers.contentDisposition = .init(.attachment, filename: attachment.fileName)
        response.headers.contentType = attachment.fileName
            .split(separator: ".")
            .last
            .flatMap { HTTPMediaType.fileExtension(String($0)) }
            ?? .binary
        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        return response
    }

    func preview(req: Request) async throws -> Response {
        let (attachment, task) = try await requiredAttachment(req, permission: .view)
        guard let preview = attachment.preview else {
            throw Abort(.unsupportedMediaType, reason: "This attachment cannot be previewed.")
        }
        let response = try await AttachmentStorageService.response(
            for: attachment,
            task: task,
            req: req
        )
        response.headers.contentDisposition = .init(.inline, filename: attachment.fileName)
        response.headers.contentType = preview.mediaType
        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        return response
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let (attachment, task) = try await requiredAttachment(req, permission: .edit)
        if AttachmentStorage.isObjectKey(attachment.storageName) {
            try await AttachmentStorageService.delete(key: attachment.storageName, for: req)
        } else {
            let path = try AttachmentStorageService.legacyPath(
                for: attachment,
                task: task,
                req: req
            )
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
        try await attachment.delete(on: req.db)
        return .noContent
    }

    private func requiredTask(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> Task {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
        return task
    }

    private func requiredAttachment(
        _ req: Request,
        permission: BoardPermission
    ) async throws -> (TaskAttachment, Task) {
        guard
            let attachmentID = req.parameters.get("attachmentID", as: UUID.self),
            let attachment = try await TaskAttachment.find(attachmentID, on: req.db),
            let task = try await Task.find(attachment.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The attachment does not exist.")
        }
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
        return (attachment, task)
    }

    private func safeFileName(_ value: String) -> String {
        String(
            value.split(whereSeparator: { $0 == "/" || $0 == "\\" })
                .last
                .map(String.init)?
                .prefix(160)
                ?? "attachment"
        )
    }
}

private struct AttachmentUploadRequest: Content {
    let file: File
}

private struct AttachmentResponse: Content {
    let id: UUID
    let fileName: String
    let contentType: String
    let byteCount: Int

    init(attachment: TaskAttachment) throws {
        self.id = try attachment.requireID()
        self.fileName = attachment.fileName
        self.contentType = attachment.contentType
        self.byteCount = attachment.byteCount
    }
}
