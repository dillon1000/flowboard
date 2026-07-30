@testable import App
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Attachment storage")
struct AttachmentStorageTests {
    @Test("Object keys separate new records from legacy volume files")
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
