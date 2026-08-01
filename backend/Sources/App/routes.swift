import Vapor

/// Registers the public API. All state-changing routes are grouped under `/api/v1`
/// so future incompatible contracts can ship without breaking current clients.
func routes(_ app: Application) throws {
    app.attachmentStorage = try AttachmentStorage.configured(for: app.environment)

    app.get("health") { _ in
        HealthResponse(status: "ok", service: "flowboard-server")
    }

    try app.register(collection: WebController())
    try app.register(collection: OAuthController())

    let api = app.grouped("api", "v1")
    api.get { _ in
        APIIndexResponse(
            name: "Flowboard REST API",
            version: "v1",
            authentication: "Session cookie from POST /api/v1/auth/login",
            boards: "/api/v1/boards",
            tasks: "/api/v1/tasks",
            taskSearch: "/api/v1/tasks/search?q={query}"
        )
    }
    try api.register(collection: AuthController())

    let protectedAPI = api.grouped(User.guardMiddleware())
    try protectedAPI.register(collection: BoardController())
    try protectedAPI.register(collection: BoardResourceController())
    try protectedAPI.register(collection: TaskController())
    try protectedAPI.register(collection: TaskResourceController())
}

private struct HealthResponse: Content {
    let status: String
    let service: String
}

private struct APIIndexResponse: Content {
    let name: String
    let version: String
    let authentication: String
    let boards: String
    let tasks: String
    let taskSearch: String
}
