import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
    func requiredBoard(
        for req: Request,
        permission: BoardPermission
    ) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await requireAccess(boardID: boardID, permission: permission, for: req)
    }

    func requiredTask(
        for req: Request,
        permission: BoardPermission
    ) async throws -> Task {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The task does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: permission, for: req)
        return task
    }

    func requiredAttachment(
        for req: Request,
        permission: BoardPermission
    ) async throws -> (TaskAttachment, Task) {
        guard
            let attachmentID = req.parameters.get("attachmentID", as: UUID.self),
            let attachment = try await TaskAttachment.find(attachmentID, on: req.db),
            let task = try await Task.find(attachment.$task.id, on: req.db)
        else {
            throw Abort(.notFound, reason: "The attachment does not exist.")
        }
        _ = try await requireAccess(boardID: task.$board.id, permission: permission, for: req)
        return (attachment, task)
    }

    func requiredTemplate(
        for req: Request,
        boardID: UUID
    ) async throws -> TaskTemplate {
        guard
            let templateID = req.parameters.get("templateID", as: UUID.self),
            let template = try await TaskTemplate.query(on: req.db)
                .filter(\.$id == templateID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The template does not exist.")
        }
        return template
    }

    func requireAccess(
        boardID: UUID,
        permission: BoardPermission,
        for req: Request
    ) async throws -> BoardAccess {
        try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: permission,
            on: req.db
        )
    }

    func uniqueSlug(_ requested: String, on database: any Database) async throws -> String {
        guard try await Board.query(on: database).filter(\.$slug == requested).first() != nil else {
            return requested
        }
        return "\(String(requested.prefix(39)))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    func slugify(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((normalized.isEmpty ? "board" : normalized).prefix(48))
    }

    /// Stores a new object in Railway in production. Development and tests retain
    /// local storage so they work without access to shared bucket credentials.
    func storeAttachment(
        _ buffer: ByteBuffer,
        key: String,
        contentType: String,
        for req: Request
    ) async throws {
        if req.application.attachmentStorage.usesRemoteStore {
            guard let data = buffer.getData(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            ) else {
                throw Abort(.badRequest, reason: "The attachment could not be read.")
            }
            do {
                try await req.application.attachmentStorage.put(
                    data: data,
                    key: key,
                    contentType: contentType,
                    using: req.client
                )
            } catch {
                req.logger.error("Attachment upload failed: \(error)")
                throw Abort(.badGateway, reason: "Attachment storage is unavailable.")
            }
            return
        }

        let path = attachmentRoot(req: req) + key
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        try await req.fileio.writeFile(buffer, at: path)
    }

    /// Returns a private object through the authenticated application route.
    /// Railway buckets remain private and never expose credentials to the browser.
    func objectResponse(key: String, for req: Request) async throws -> Response {
        guard req.application.attachmentStorage.usesRemoteStore else {
            return try await req.fileio.asyncStreamFile(at: attachmentRoot(req: req) + key)
        }
        do {
            let data = try await req.application.attachmentStorage.get(
                key: key,
                using: req.client
            )
            return Response(status: .ok, body: .init(data: data))
        } catch {
            req.logger.error("Attachment download failed: \(error)")
            throw Abort(.badGateway, reason: "Attachment storage is unavailable.")
        }
    }

    func storedAttachmentResponse(
        _ attachment: TaskAttachment,
        task: Task,
        for req: Request
    ) async throws -> Response {
        if AttachmentStorage.isObjectKey(attachment.storageName) {
            return try await objectResponse(key: attachment.storageName, for: req)
        }
        return try await req.fileio.asyncStreamFile(
            at: legacyAttachmentPath(attachment, task: task, req: req)
        )
    }

    func legacyAttachmentPath(
        _ attachment: TaskAttachment,
        task: Task,
        req: Request
    ) throws -> String {
        attachmentRoot(req: req)
            + task.$board.id.uuidString + "/"
            + (try task.requireID()).uuidString + "/"
            + attachment.storageName
    }

    /// Deletes bucket objects before Fluent cascades their metadata. A failed S3
    /// operation stops the database delete so the user can retry without orphans.
    func deleteStoredAttachments(
        _ attachments: [TaskAttachment],
        for req: Request
    ) async throws {
        for attachment in attachments
        where AttachmentStorage.isObjectKey(attachment.storageName) {
            try await deleteStoredAttachment(key: attachment.storageName, for: req)
        }
    }

    func deleteStoredAttachment(key: String, for req: Request) async throws {
        guard req.application.attachmentStorage.usesRemoteStore else {
            try? FileManager.default.removeItem(atPath: attachmentRoot(req: req) + key)
            return
        }
        do {
            try await req.application.attachmentStorage.delete(
                key: key,
                using: req.client
            )
        } catch {
            req.logger.error("Attachment deletion failed: \(error)")
            throw Abort(.badGateway, reason: "Attachment storage is unavailable.")
        }
    }

    /// Removes both the legacy directory and the new local development directory.
    /// Production normally has only the legacy path because new files use Railway.
    func removeLocalAttachmentDirectories(
        boardID: UUID,
        taskID: UUID? = nil,
        req: Request
    ) {
        let suffix = taskID.map { "/\($0.uuidString)" } ?? ""
        let root = attachmentRoot(req: req)
        try? FileManager.default.removeItem(
            atPath: root + boardID.uuidString + suffix
        )
        try? FileManager.default.removeItem(
            atPath: root + "attachments/" + boardID.uuidString + suffix
        )
    }

    func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func labels(_ value: String?) -> [String] {
        Array(
            (value ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(6)
        )
    }

    func parseDate(_ value: String?) -> Date? {
        guard let value = clean(value) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: 12
            )
        )
    }

    func safeReturn(_ value: String?, fallback: String) -> String {
        guard
            let value,
            value == "/app" || value.hasPrefix("/app?") || value.hasPrefix("/app/"),
            !value.hasPrefix("//")
        else {
            return fallback
        }
        return value
    }

    func safeFileName(_ value: String) -> String {
        String(
            value
                .split(whereSeparator: { $0 == "/" || $0 == "\\" })
                .last
                .map(String.init)?
                .prefix(160)
                ?? "attachment"
        )
    }

    func attachmentRoot(req: Request) -> String {
        req.application.directory.workingDirectory + "Uploads/"
    }
}
