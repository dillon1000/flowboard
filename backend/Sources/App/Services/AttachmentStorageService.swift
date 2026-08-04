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
        req: Request
    ) async throws -> Response {
        let key = try validKey(attachment.storageName)
        guard req.application.attachmentStorage.usesRemoteStore else {
            return try await req.fileio.asyncStreamFile(at: root(for: req) + key)
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

    /// Deletes object bytes before metadata cascades. A storage failure leaves
    /// the metadata intact, which lets the user retry without creating an orphan.
    static func delete(_ attachments: [TaskAttachment], for req: Request) async throws {
        for attachment in attachments {
            try await delete(key: attachment.storageName, for: req)
        }
    }

    static func delete(key: String, for req: Request) async throws {
        let key = try validKey(key)
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
        try? FileManager.default.removeItem(
            atPath: root(for: req) + "attachments/" + boardID.uuidString + suffix
        )
    }

    private static func validKey(_ value: String) throws -> String {
        guard AttachmentStorage.isObjectKey(value) else {
            throw Abort(.notFound, reason: "The attachment file does not exist.")
        }
        return value
    }

    private static func root(for req: Request) -> String {
        req.application.directory.workingDirectory + "Uploads/"
    }
}
