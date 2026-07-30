@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

/// Registers through the public API and returns the cookie plus the board that
/// the registration transaction creates. Tests then exercise the real guard.
func register(
    on app: Application
) async throws -> (cookie: String, boardID: UUID, userID: UUID) {
    let input = RegisterRequest(
        name: "Test User",
        email: "\(UUID().uuidString.lowercased())@example.com",
        password: "correct-horse-battery"
    )
    let response = try await app.testing().sendRequest(
        .POST,
        "api/v1/auth/register",
        beforeRequest: { request in
            try request.content.encode(input)
        }
    )
    #expect(response.status == .created)

    let setCookie = try #require(response.headers[.setCookie].first)
    let cookie = String(try #require(setCookie.split(separator: ";").first))
    let user = try response.content.decode(UserResponse.self)
    let board = try #require(
        try await Board.query(on: app.db)
            .filter(\.$owner.$id == user.id)
            .first()
    )
    return (cookie, try board.requireID(), user.id)
}
