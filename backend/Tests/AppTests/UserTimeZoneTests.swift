@testable import App
import Fluent
import Testing
import Vapor
import VaporTesting

@Suite("User time zones")
struct UserTimeZoneTests {
    @Test("Profile settings store a valid IANA zone")
    func updatesProfileTimeZone() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let initialUser = try #require(try await User.find(session.userID, on: app.db))
            #expect(initialUser.timeZoneIdentifier == "UTC")

            let updated = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/auth/me",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        UpdateProfileRequest(name: "Test User", timeZone: "America/Chicago")
                    )
                }
            )
            #expect(updated.status == .ok)
            #expect(try updated.content.decode(UserResponse.self).timeZone == "America/Chicago")

            let workspace = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace",
                headers: ["Cookie": session.cookie]
            )
            #expect(workspace.status == .ok)
            expectContains(workspace.body.string, #""userTimeZone":"America/Chicago""#)

            let rejected = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/auth/me",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        UpdateProfileRequest(name: "Test User", timeZone: "Mars/Olympus")
                    )
                }
            )
            #expect(rejected.status == .unprocessableEntity)
        }
    }
}
