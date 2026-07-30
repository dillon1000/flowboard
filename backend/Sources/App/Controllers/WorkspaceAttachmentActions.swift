import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
    func createAttachment(req: Request) async throws -> Response {
        let task = try await requiredTask(for: req, permission: .edit)
        let input = try req.content.decode(AttachmentForm.self)
        guard input.file.data.readableBytes <= 10_000_000 else {
            throw Abort(.payloadTooLarge, reason: "Attachments must be 10 MB or smaller.")
        }
        let boardID = task.$board.id
        let taskID = try task.requireID()
        let fileExtension = input.file.extension?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let generatedName = UUID().uuidString + (fileExtension.map { ".\($0)" } ?? "")
        let storageName = AttachmentStorage.objectKey(
            boardID: boardID,
            taskID: taskID,
            storageName: generatedName
        )
        let contentType = input.file.contentType?.serialize() ?? "application/octet-stream"
        try await storeAttachment(
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
            try? await deleteStoredAttachment(key: storageName, for: req)
            throw error
        }
        return req.redirect(to: "/app/tasks/\(taskID)")
    }

    func downloadAttachment(req: Request) async throws -> Response {
        let (attachment, task) = try await requiredAttachment(for: req, permission: .view)
        let response = try await storedAttachmentResponse(attachment, task: task, for: req)
        response.headers.contentDisposition = .init(.attachment, filename: attachment.fileName)
        if let mediaType = attachment.fileName
            .split(separator: ".")
            .last
            .flatMap({ HTTPMediaType.fileExtension(String($0)) })
        {
            response.headers.contentType = mediaType
        }
        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        return response
    }

    /// Serves only allowlisted passive media inline. Other uploads stay
    /// download-only even when a client requests the preview route directly.
    func previewAttachment(req: Request) async throws -> Response {
        let (attachment, task) = try await requiredAttachment(for: req, permission: .view)
        guard let preview = attachment.preview else {
            throw Abort(.unsupportedMediaType, reason: "This attachment cannot be previewed.")
        }
        let response = try await storedAttachmentResponse(attachment, task: task, for: req)
        response.headers.contentDisposition = .init(.inline, filename: attachment.fileName)
        response.headers.contentType = preview.mediaType
        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        return response
    }

    /// Removes file bytes before metadata so a storage failure leaves a record
    /// that the user can retry. Missing local files count as already removed.
    func deleteAttachment(req: Request) async throws -> Response {
        let (attachment, task) = try await requiredAttachment(for: req, permission: .edit)
        if AttachmentStorage.isObjectKey(attachment.storageName) {
            try await deleteStoredAttachment(key: attachment.storageName, for: req)
        } else {
            let path = try legacyAttachmentPath(attachment, task: task, req: req)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
        try await attachment.delete(on: req.db)
        return req.redirect(to: "/app/tasks/\(try task.requireID())")
    }

    func updateProfile(req: Request) async throws -> Response {
        let input = try req.content.decode(UpdateProfileRequest.self)
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(name.count) else {
            throw Abort(.unprocessableEntity, reason: "Use a name between 2 and 80 characters.")
        }
        let user = try req.auth.require(User.self)
        user.name = name
        try await user.update(on: req.db)
        return req.redirect(to: "/app/settings")
    }
}
