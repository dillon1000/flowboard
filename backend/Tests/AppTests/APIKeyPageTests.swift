@testable import App
import Fluent
import Testing
import Vapor
import VaporTesting

@Suite("API key settings data")
struct APIKeyPageTests {
    @Test("Page data lists keys without exposing the stored secret")
    func pageDataAndLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let created = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/api-keys",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateAPIKeyRequest(name: "Documentation test", expiresAt: nil)
                    )
                }
            )
            #expect(created.status == .created)
            let createdKey = try created.content.decode(CreatedAPIKeyResponse.self)
            #expect(createdKey.key.hasPrefix("fbk_"))

            let stored = try #require(
                try await APIKeyCredential.query(on: app.db)
                    .filter(\.$user.$id == session.userID)
                    .first()
            )
            #expect(stored.keyHash == APIKeyService.hash(createdKey.key))

            let pageData = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/settings/api-keys",
                headers: ["Cookie": session.cookie]
            )
            #expect(pageData.status == .ok)
            expectContains(pageData.body.string, "Documentation test")
            expectContains(pageData.body.string, stored.keyPrefix)
            expectContains(pageData.body.string, "\"hasCreatedKey\":false")
            #expect(!pageData.body.string.contains(createdKey.key))

            let revoked = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/api-keys/\(try stored.requireID())",
                headers: ["Cookie": session.cookie]
            )
            #expect(revoked.status == .noContent)
            #expect(try await APIKeyCredential.find(stored.requireID(), on: app.db) == nil)
        }
    }
}
