import Vapor

/// Registers the public API. All state-changing routes are grouped under `/api/v1`
/// so future incompatible contracts can ship without breaking current clients.
func routes(_ app: Application) throws {
    app.get("health") { _ in
        HealthResponse(status: "ok", service: "flowboard-server")
    }

    try app.register(collection: WebController())

    let api = app.grouped("api", "v1")
    try api.register(collection: AuthController())

    let protectedAPI = api.grouped(User.guardMiddleware())
    try protectedAPI.register(collection: BoardController())
    try protectedAPI.register(collection: TaskController())
}

private struct HealthResponse: Content {
    let status: String
    let service: String
}
