import Vapor

/// Exposes the only unauthenticated state-changing Tap route. The bearer token
/// limits the request to one server-defined action and never grants general API access.
struct TapExecutionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("taps", "execute", use: execute)
    }

    func execute(req: Request) async throws -> TapExecutionResponse {
        let input = try req.content.decode(TapExecutionRequest.self)
        return try await TapActionService.execute(input, on: req.db)
    }
}
