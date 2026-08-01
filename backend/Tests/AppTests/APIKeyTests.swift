@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("API key authentication")
struct APIKeyTests {
    @Test("A user can create, use, list, and revoke an API key")
    func lifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let create = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/api-keys",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateAPIKeyRequest(name: "Release automation", expiresAt: nil)
                    )
                }
            )
            #expect(create.status == .created)
            let created = try create.content.decode(CreatedAPIKeyResponse.self)
            #expect(created.key.hasPrefix("fbk_"))
            #expect(created.key.count == 68)
            #expect(created.prefix == String(created.key.prefix(12)))

            let stored = try #require(
                try await APIKeyCredential.find(created.id, on: app.db)
            )
            #expect(stored.keyHash == APIKeyService.hash(created.key))
            #expect(stored.keyHash != created.key)

            let bearer = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: ["Authorization": "Bearer \(created.key)"]
            )
            #expect(bearer.status == .ok)
            #expect(try bearer.content.decode([BoardSummaryResponse].self).count == 1)

            // CSRF middleware can create an anonymous session cookie. Reusing that
            // cookie must not retain the identity that came from the API key.
            if let setCookie = bearer.headers[.setCookie].first {
                let anonymousCookie = String(try #require(setCookie.split(separator: ";").first))
                let cookieOnly = try await app.testing().sendRequest(
                    .GET,
                    "api/v1/boards",
                    headers: ["Cookie": anonymousCookie]
                )
                #expect(cookieOnly.status == .unauthorized)
            }

            let list = try await app.testing().sendRequest(
                .GET,
                "api/v1/auth/api-keys",
                headers: ["Cookie": session.cookie]
            )
            #expect(list.status == .ok)
            let keys = try list.content.decode([APIKeyResponse].self)
            #expect(keys.map(\.id) == [created.id])
            #expect(keys[0].lastUsedAt != nil)
            let listBody = list.body.getString(at: 0, length: list.body.readableBytes)
            #expect(listBody?.contains(created.key) == false)

            let revoke = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/api-keys/\(created.id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(revoke.status == .noContent)

            let afterRevoke = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: ["Authorization": "Bearer \(created.key)"]
            )
            #expect(afterRevoke.status == .unauthorized)
        }
    }

    @Test("API keys enforce session management, ownership, expiry, and strict headers")
    func securityBoundaries() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let otherUser = try await register(on: app)
            let created = try await createKey(cookie: owner.cookie, on: app)

            let keyCannotCreateKey = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/api-keys",
                headers: ["Authorization": "Bearer \(created.key)"],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateAPIKeyRequest(name: "Replacement", expiresAt: nil)
                    )
                }
            )
            #expect(keyCannotCreateKey.status == .unauthorized)

            let wrongOwner = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/auth/api-keys/\(created.id)",
                headers: ["Cookie": otherUser.cookie]
            )
            #expect(wrongOwner.status == .notFound)

            let badHeader = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: [
                    "Authorization": "Basic invalid",
                    "Cookie": owner.cookie,
                ]
            )
            #expect(badHeader.status == .unauthorized)

            let pastExpiry = try await app.testing().sendRequest(
                .POST,
                "api/v1/auth/api-keys",
                headers: ["Cookie": owner.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateAPIKeyRequest(
                            name: "Already expired",
                            expiresAt: Date(timeIntervalSinceNow: -60)
                        )
                    )
                }
            )
            #expect(pastExpiry.status == .unprocessableEntity)

            let expired = APIKeyService.generate()
            try await APIKeyCredential(
                userID: owner.userID,
                name: "Expired key",
                keyHash: expired.hash,
                keyPrefix: expired.visiblePrefix,
                expiresAt: Date(timeIntervalSinceNow: -60)
            ).create(on: app.db)
            let expiredRequest = try await app.testing().sendRequest(
                .GET,
                "api/v1/boards",
                headers: ["Authorization": "Bearer \(expired.raw)"]
            )
            #expect(expiredRequest.status == .unauthorized)
        }
    }

    /// Creates a key through the session-only public endpoint so security tests do
    /// not bypass validation, hashing, or the response contract.
    private func createKey(
        cookie: String,
        on app: Application
    ) async throws -> CreatedAPIKeyResponse {
        let response = try await app.testing().sendRequest(
            .POST,
            "api/v1/auth/api-keys",
            headers: ["Cookie": cookie],
            beforeRequest: { request in
                try request.content.encode(
                    CreateAPIKeyRequest(name: "Test key", expiresAt: nil)
                )
            }
        )
        #expect(response.status == .created)
        return try response.content.decode(CreatedAPIKeyResponse.self)
    }
}
