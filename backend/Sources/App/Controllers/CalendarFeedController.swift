import Fluent
import Vapor

/// Serves the token-authenticated, read-only calendar. Invalid and revoked tokens
/// return the same 404 response so the endpoint does not disclose feed state.
struct CalendarFeedController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("calendar-feed", ":token", "calendar.ics", use: feed)
    }

    func feed(req: Request) async throws -> Response {
        guard
            let token = req.parameters.get("token"),
            let credential = try await CalendarFeedService.authenticate(token, on: req.db)
        else {
            throw Abort(.notFound)
        }
        return try await CalendarFeedService.response(credential: credential, on: req.db)
    }
}

/// Creates, rotates, and revokes the signed-in user's subscription token. These
/// routes are session-only because a feed token must not mint its replacement.
struct CalendarFeedManagementController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let feed = routes.grouped("calendar-feed")
        feed.get(use: status)
        feed.post(use: rotate)
        feed.delete(use: revoke)
    }

    func status(req: Request) async throws -> CalendarFeedStatusResponse {
        let userID = try req.auth.require(User.self).requireID()
        let credential = try await CalendarFeedCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        return CalendarFeedStatusResponse(credential: credential)
    }

    func rotate(req: Request) async throws -> Response {
        let userID = try req.auth.require(User.self).requireID()
        let created = try await CalendarFeedService.rotate(userID: userID, on: req.db)
        return try await CreatedCalendarFeedResponse(
            token: created.raw,
            prefix: created.credential.tokenPrefix
        )
        .encodeResponse(status: .created, for: req)
    }

    func revoke(req: Request) async throws -> HTTPStatus {
        let userID = try req.auth.require(User.self).requireID()
        if let credential = try await CalendarFeedCredential.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        {
            try await credential.delete(on: req.db)
        }
        return .noContent
    }
}
