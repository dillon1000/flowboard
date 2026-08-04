import Fluent
import Foundation
import Vapor

/// Manages bearer Tap actions through JSON. Raw credentials appear only in a
/// create or rotate response because the database stores their digests.
struct TapActionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let actions = routes.grouped("boards", ":boardID", "tap-actions")
        actions.post(use: create)
        actions.patch(":tapActionID", use: update)
        actions.post(":tapActionID", "rotate", use: rotate)
        actions.delete(":tapActionID", use: delete)
    }

    func create(req: Request) async throws -> Response {
        let access = try await requiredBoard(req)
        let input = try req.content.decode(TapActionMutationRequest.self)
        let credential = TapTokenService.generate()
        let url = try TapTokenService.makeURL(rawToken: credential.raw, for: req)
        let action = try await TapActionService.create(
            board: access.board,
            definition: try definition(from: input),
            credential: credential,
            on: req.db
        )
        return try await response(action: action, url: url, status: .created, for: req)
    }

    func update(req: Request) async throws -> Response {
        let access = try await requiredBoard(req)
        let action = try await requiredAction(req, boardID: access.board.requireID())
        let input = try req.content.decode(TapActionMutationRequest.self)
        if input.name == nil {
            guard let isEnabled = input.isEnabled else {
                throw Abort(.unprocessableEntity, reason: "The Tap action update is empty.")
            }
            action.isEnabled = isEnabled
            try await action.update(on: req.db)
        } else {
            try await TapActionService.update(
                action,
                board: access.board,
                definition: try definition(from: input),
                on: req.db
            )
        }
        return try await response(action: action, url: nil, status: .ok, for: req)
    }

    /// Builds the replacement URL before it changes storage. A bad public base
    /// URL therefore leaves the active credential unchanged.
    func rotate(req: Request) async throws -> Response {
        let access = try await requiredBoard(req)
        let action = try await requiredAction(req, boardID: access.board.requireID())
        let credential = TapTokenService.generate()
        let url = try TapTokenService.makeURL(rawToken: credential.raw, for: req)
        try await TapActionService.rotate(action, credential: credential, on: req.db)
        return try await response(action: action, url: url, status: .ok, for: req)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let access = try await requiredBoard(req)
        let action = try await requiredAction(req, boardID: access.board.requireID())
        try await action.delete(on: req.db)
        return .noContent
    }

    private func requiredBoard(_ req: Request) async throws -> BoardAccess {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }
        return try await BoardAccessService.require(
            boardID: boardID,
            userID: req.auth.require(User.self).requireID(),
            permission: .admin,
            on: req.db
        )
    }

    private func requiredAction(_ req: Request, boardID: UUID) async throws -> TapAction {
        guard
            let actionID = req.parameters.get("tapActionID", as: UUID.self),
            let action = try await TapAction.query(on: req.db)
                .filter(\.$id == actionID)
                .filter(\.$board.$id == boardID)
                .first()
        else {
            throw Abort(.notFound, reason: "The Tap action does not exist.")
        }
        return action
    }

    private func definition(
        from input: TapActionMutationRequest
    ) throws -> TapActionService.Definition {
        guard
            let name = input.name,
            let kind = input.kind,
            let status = input.status
        else {
            throw Abort(.unprocessableEntity, reason: "Name, action, and status are required.")
        }
        return TapActionService.Definition(
            name: name,
            displayDescription: input.displayDescription,
            kind: kind,
            targetTaskID: input.targetTaskID,
            configuration: TapActionConfiguration(
                status: status,
                priority: input.priority
            ),
            expiresAt: try expiry(from: input.expiresAt),
            maxUses: input.maxUses,
            cooldownSeconds: input.cooldownSeconds ?? 3
        )
    }

    private func expiry(from value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw Abort(.unprocessableEntity, reason: "Enter a valid Tap action expiry date.")
        }
        return date
    }

    private func response(
        action: TapAction,
        url: String?,
        status: HTTPResponseStatus,
        for req: Request
    ) async throws -> Response {
        let response = try await TapActionMutationResponse(
            id: action.requireID(),
            url: url
        ).encodeResponse(status: status, for: req)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}

private struct TapActionMutationRequest: Content {
    let name: String?
    let displayDescription: String?
    let kind: TapActionKind?
    let targetTaskID: UUID?
    let status: String?
    let priority: String?
    let expiresAt: String?
    let maxUses: Int?
    let cooldownSeconds: Int?
    let isEnabled: Bool?
}

private struct TapActionMutationResponse: Content {
    let id: UUID
    let url: String?
}
