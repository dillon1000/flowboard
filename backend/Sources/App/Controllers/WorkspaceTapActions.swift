import Fluent
import Foundation
import Vapor

extension WorkspaceActionController {
    /// Creates one capability and renders its full URL once. The response is not
    /// cached because the raw token cannot be recovered from the stored digest.
    func createTapAction(req: Request) async throws -> Response {
        let created: (action: TapAction, rawToken: String)
        let tapURL: String
        do {
            let access = try await requiredBoard(for: req, permission: .admin)
            let input = try req.content.decode(TapActionForm.self)
            let credential = TapTokenService.generate()
            tapURL = try TapTokenService.makeURL(rawToken: credential.raw, for: req)
            let action = try await TapActionService.create(
                board: access.board,
                definition: try tapDefinition(from: input),
                credential: credential,
                on: req.db
            )
            created = (action, credential.raw)
        } catch {
            return try await tapActionErrorResponse(error, for: req)
        }

        do {
            let page = try await AppPageController().renderBoardSettingsPage(
                for: req,
                createdTapURL: tapURL
            )
            let response = try await page.encodeResponse(status: .created, for: req)
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return response
        } catch {
            // A capability whose raw URL was not shown cannot be programmed. Its
            // row is removed so no unreachable credential remains active.
            try? await created.action.delete(on: req.db)
            throw error
        }
    }

    func updateTapAction(req: Request) async throws -> Response {
        do {
            let access = try await requiredBoard(for: req, permission: .admin)
            let action = try await requiredTapAction(for: req, boardID: access.board.requireID())
            let input = try req.content.decode(TapActionForm.self)
            try await TapActionService.update(
                action,
                board: access.board,
                definition: try tapDefinition(from: input),
                on: req.db
            )
            return req.redirect(to: tapSettingsPath(boardID: try access.board.requireID()))
        } catch {
            return try await tapActionErrorResponse(error, for: req)
        }
    }

    func toggleTapAction(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let action = try await requiredTapAction(for: req, boardID: access.board.requireID())
        action.isEnabled.toggle()
        try await action.update(on: req.db)
        return req.redirect(to: tapSettingsPath(boardID: try access.board.requireID()))
    }

    /// Rotates a copied or exposed URL and resets its use counter. The new URL
    /// is built before storage changes, so an invalid public base URL leaves the old tag active.
    func rotateTapAction(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let action = try await requiredTapAction(for: req, boardID: access.board.requireID())
        let credential = TapTokenService.generate()
        let tapURL = try TapTokenService.makeURL(rawToken: credential.raw, for: req)
        try await TapActionService.rotate(action, credential: credential, on: req.db)
        let page = try await AppPageController().renderBoardSettingsPage(
            for: req,
            createdTapURL: tapURL
        )
        let response = try await page.encodeResponse(status: .ok, for: req)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }

    func deleteTapAction(req: Request) async throws -> Response {
        let access = try await requiredBoard(for: req, permission: .admin)
        let action = try await requiredTapAction(for: req, boardID: access.board.requireID())
        try await action.delete(on: req.db)
        return req.redirect(to: tapSettingsPath(boardID: try access.board.requireID()))
    }

    private func requiredTapAction(for req: Request, boardID: UUID) async throws -> TapAction {
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

    private func tapDefinition(from input: TapActionForm) throws -> TapActionService.Definition {
        guard let kind = TapActionKind(rawValue: input.kind) else {
            throw Abort(.unprocessableEntity, reason: "Select a supported Tap action.")
        }
        let maxUses = try optionalInteger(input.maxUses, field: "Use limit")
        let cooldownSeconds = try optionalInteger(
            input.cooldownSeconds,
            field: "Cooldown"
        ) ?? 3
        let expiresAt = try tapExpiry(input.expiresAt)
        return TapActionService.Definition(
            name: input.name,
            kind: kind,
            targetTaskID: clean(input.targetTaskID).flatMap(UUID.init(uuidString:)),
            configuration: TapActionConfiguration(
                title: input.title,
                description: input.description,
                status: input.status,
                priority: input.priority,
                labels: labels(input.labels)
            ),
            expiresAt: expiresAt,
            maxUses: maxUses,
            cooldownSeconds: cooldownSeconds
        )
    }

    private func optionalInteger(_ value: String?, field: String) throws -> Int? {
        guard let value = clean(value) else { return nil }
        guard let number = Int(value) else {
            throw Abort(.unprocessableEntity, reason: "\(field) must be a whole number.")
        }
        return number
    }

    /// Date-only expiry values remain active through the selected UTC day.
    private func tapExpiry(_ value: String?) throws -> Date? {
        guard let value = clean(value) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw Abort(.unprocessableEntity, reason: "Enter a valid Tap action expiry date.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2],
                hour: 23,
                minute: 59,
                second: 59
            )
        )
    }

    private func tapActionErrorResponse(_ error: any Error, for req: Request) async throws -> Response {
        let message = (error as? any AbortError)?.reason
            ?? "The Tap action could not be saved. Try again."
        let page = try await AppPageController().renderBoardSettingsPage(
            for: req,
            tapError: message
        )
        return try await page.encodeResponse(status: .unprocessableEntity, for: req)
    }

    private func tapSettingsPath(boardID: UUID) -> String {
        "/app/boards/\(boardID)/settings#tap-actions"
    }
}
