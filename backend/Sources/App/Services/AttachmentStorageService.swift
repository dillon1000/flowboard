import Foundation
import Vapor

/// Keeps private attachment bytes in the configured object store or local
/// development directory. Database metadata changes happen only after storage succeeds.
enum AttachmentStorageService {
    static func store(
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

        let path = root(for: req) + key
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )
        try await req.fileio.writeFile(buffer, at: path)
    }

    static func response(
        for attachment: TaskAttachment,
        task: Task,
        req: Request
    ) async throws -> Response {
        if AttachmentStorage.isObjectKey(attachment.storageName) {
            guard req.application.attachmentStorage.usesRemoteStore else {
                return try await req.fileio.asyncStreamFile(
                    at: root(for: req) + attachment.storageName
                )
            }
            do {
                let data = try await req.application.attachmentStorage.get(
                    key: attachment.storageName,
                    using: req.client
                )
                return Response(status: .ok, body: .init(data: data))
            } catch {
                req.logger.error("Attachment download failed: \(error)")
                throw Abort(.badGateway, reason: "Attachment storage is unavailable.")
            }
        }
        return try await req.fileio.asyncStreamFile(
            at: try legacyPath(for: attachment, task: task, req: req)
        )
    }

    /// Deletes object bytes before metadata cascades. A storage failure leaves
    /// the metadata intact, which lets the user retry without creating an orphan.
    static func delete(_ attachments: [TaskAttachment], for req: Request) async throws {
        for attachment in attachments {
            if AttachmentStorage.isObjectKey(attachment.storageName) {
                try await delete(key: attachment.storageName, for: req)
            }
        }
    }

    static func delete(key: String, for req: Request) async throws {
        guard req.application.attachmentStorage.usesRemoteStore else {
            try? FileManager.default.removeItem(atPath: root(for: req) + key)
            return
        }
        do {
            try await req.application.attachmentStorage.delete(key: key, using: req.client)
        } catch {
            req.logger.error("Attachment deletion failed: \(error)")
            throw Abort(.badGateway, reason: "Attachment storage is unavailable.")
        }
    }

    static func removeLocalDirectories(
        boardID: UUID,
        taskID: UUID? = nil,
        req: Request
    ) {
        let suffix = taskID.map { "/\($0.uuidString)" } ?? ""
        try? FileManager.default.removeItem(atPath: root(for: req) + boardID.uuidString + suffix)
        try? FileManager.default.removeItem(
            atPath: root(for: req) + "attachments/" + boardID.uuidString + suffix
        )
    }

    static func legacyPath(
        for attachment: TaskAttachment,
        task: Task,
        req: Request
    ) throws -> String {
        root(for: req)
            + task.$board.id.uuidString + "/"
            + (try task.requireID()).uuidString + "/"
            + attachment.storageName
    }

    private static func root(for req: Request) -> String {
        req.application.directory.workingDirectory + "Uploads/"
    }
}
