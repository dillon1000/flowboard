@testable import App
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Attachment storage")
struct AttachmentStorageTests {
    @Test("Object keys use the strict attachment namespace")
    func objectKeyFormat() {
        let boardID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let taskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let key = AttachmentStorage.objectKey(
            boardID: boardID,
            taskID: taskID,
            storageName: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC.pdf"
        )

        #expect(
            key
                == "attachments/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/"
                + "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB/"
                + "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC.pdf"
        )
        #expect(AttachmentStorage.isObjectKey(key))
        #expect(!AttachmentStorage.isObjectKey("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC.pdf"))
        #expect(!AttachmentStorage.isObjectKey("attachments/../../secret"))
    }

    @Test("Legacy attachments remain readable and deletable")
    func legacyAttachmentLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let task = Task(
                boardID: session.boardID,
                title: "Legacy attachment task",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()
            let storageName = "legacy-\(UUID().uuidString).txt"
            let attachment = TaskAttachment(
                taskID: taskID,
                uploadedByID: session.userID,
                fileName: "legacy.txt",
                storageName: storageName,
                contentType: "text/plain",
                byteCount: 17
            )
            try await attachment.create(on: app.db)
            let attachmentID = try attachment.requireID()
            let boardPath = app.directory.workingDirectory + "Uploads/" + session.boardID.uuidString
            let filePath = boardPath + "/" + taskID.uuidString + "/" + storageName
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: filePath).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(atPath: boardPath) }
            try Data("legacy attachment".utf8).write(to: URL(fileURLWithPath: filePath))

            let download = try await app.testing().sendRequest(
                .GET,
                "api/v1/attachments/\(attachmentID)",
                headers: ["Cookie": session.cookie]
            )
            #expect(download.status == .ok)
            let body = try #require(download.body)
            #expect(body.getString(at: body.readerIndex, length: body.readableBytes) == "legacy attachment")

            let deleted = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/attachments/\(attachmentID)",
                headers: ["Cookie": session.cookie]
            )
            #expect(deleted.status == .noContent)
            #expect(!FileManager.default.fileExists(atPath: filePath))
            #expect(try await TaskAttachment.find(attachmentID, on: app.db) == nil)
        }
    }

    @Test("Railway bucket round trip when enabled")
    func railwayBucketRoundTrip() async throws {
        guard Environment.get("RUN_LIVE_BUCKET_TESTS") == "1" else {
            return
        }

        // The opt-in probe writes a unique object, reads it through the same client
        // as production, and always tries to delete it before returning.
        try await withApp(configure: configure) { app in
            let storage = app.attachmentStorage
            let key = AttachmentStorage.objectKey(
                boardID: UUID(),
                taskID: UUID(),
                storageName: "railway-probe.txt"
            )
            let expected = Data("focalpoint attachment probe".utf8)

            do {
                try await storage.put(
                    data: expected,
                    key: key,
                    contentType: "text/plain",
                    using: app.client
                )
                let actual = try await storage.get(key: key, using: app.client)
                #expect(actual == expected)
                try await storage.delete(key: key, using: app.client)
            } catch {
                try? await storage.delete(key: key, using: app.client)
                throw error
            }
        }
    }
}
