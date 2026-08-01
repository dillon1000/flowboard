@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("API key settings page")
struct APIKeyPageTests {
    @Test("The page documents API use and manages keys without persisting the secret")
    func documentationAndLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let initialPage = try await app.testing().sendRequest(
                .GET,
                "app/settings/api-keys",
                headers: ["Cookie": session.cookie]
            )
            #expect(initialPage.status == .ok)
            expectContains(initialPage.body.string, "Use an API key")
            expectContains(initialPage.body.string, "Authorization: Bearer fbk_YOUR_KEY")
            expectContains(initialPage.body.string, "/tasks/search?q=release&amp;priority=high")
            expectContains(initialPage.body.string, "GET, POST /boards")
            let csrfToken = try csrfToken(from: initialPage.body.string)

            let createdPage = try await app.testing().sendRequest(
                .POST,
                "app/settings/api-keys",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        ["name": "Documentation test"],
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(createdPage.status == .created)
            #expect(createdPage.headers.first(name: .cacheControl) == "no-store")
            expectContains(createdPage.body.string, "This secret will not appear again")
            let rawKey = try createdKey(from: createdPage.body.string)
            #expect(rawKey.hasPrefix("fbk_"))

            let stored = try #require(
                try await APIKeyCredential.query(on: app.db)
                    .filter(\.$user.$id == session.userID)
                    .first()
            )
            #expect(stored.keyHash == APIKeyService.hash(rawKey))

            let laterPage = try await app.testing().sendRequest(
                .GET,
                "app/settings/api-keys",
                headers: ["Cookie": session.cookie]
            )
            #expect(laterPage.status == .ok)
            #expect(!laterPage.body.string.contains(rawKey))
            expectContains(laterPage.body.string, "Documentation test")
            expectContains(laterPage.body.string, "\(stored.keyPrefix)…")

            let revoke = try await app.testing().sendRequest(
                .POST,
                "app/settings/api-keys/\(try stored.requireID())/revoke",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ]
            )
            #expect(revoke.status == .seeOther)
            #expect(revoke.headers.first(name: .location) == "/app/settings/api-keys")
            #expect(try await APIKeyCredential.find(stored.requireID(), on: app.db) == nil)
        }
    }

    private func csrfToken(from page: String) throws -> String {
        let marker = #"name="csrf-token" content=""#
        let start = try #require(page.range(of: marker)?.upperBound)
        let end = try #require(page[start...].firstIndex(of: "\""))
        return String(page[start..<end])
    }

    private func createdKey(from page: String) throws -> String {
        let marker = #"<code class="api-key-secret">"#
        let start = try #require(page.range(of: marker)?.upperBound)
        let end = try #require(page[start...].range(of: "</code>")?.lowerBound)
        return String(page[start..<end])
    }
}
