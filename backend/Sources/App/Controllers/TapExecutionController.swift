import Vapor

/// Exposes the only unauthenticated state-changing Tap route. The bearer token
/// limits the request to one server-defined action and never grants general API access.
struct TapExecutionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("taps", "prepare", use: prepare)
        routes.post("taps", "execute", use: execute)
    }

    /// Loads field choices for a bearer action without changing task data.
    func prepare(req: Request) async throws -> TapPreparationResponse {
        try await TapActionService.prepare(
            try req.content.decode(TapPreparationRequest.self),
            on: req.db
        )
    }

    func execute(req: Request) async throws -> TapExecutionResponse {
        let input = try req.content.decode(TapExecutionRequest.self)
        return try await TapActionService.execute(input, on: req.db)
    }
}
