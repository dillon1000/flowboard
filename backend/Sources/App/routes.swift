import Vapor

/// Registers the public API. All state-changing routes are grouped under `/api/v1`
/// so future incompatible contracts can ship without breaking current clients.
func routes(_ app: Application) throws {
    app.attachmentStorage = try AttachmentStorage.configured(for: app.environment)

    app.get("health") { _ in
        HealthResponse(status: "ok", service: "flowboard-server")
    }

    // OAuth callbacks create browser sessions. Resource routes use separate
    // middleware so API keys never become sessions.
    let sessionRoutes = app.grouped(User.sessionAuthenticator())
    try sessionRoutes.register(collection: OAuthController())

    let api = app.grouped("api", "v1")
    api.get { _ in
        APIIndexResponse(
            name: "Flowboard REST API",
            version: "v1",
            authentication: "Session cookie or Authorization: Bearer API key",
            apiKeys: "/api/v1/auth/api-keys",
            boards: "/api/v1/boards",
            tasks: "/api/v1/tasks",
            taskSearch: "/api/v1/tasks/search?q={query}"
        )
    }
    try api.grouped(User.sessionAuthenticator()).register(collection: AuthController())
    try api.register(collection: TapExecutionController())

    // SvelteKit requests these presentation-ready models during server rendering.
    // They are session-only because they include private workspace navigation.
    let workspace = api
        .grouped(User.sessionAuthenticator(), User.guardMiddleware())
        .grouped("workspace")
    try workspace.register(collection: AppPageController())

    let protectedAPI = api.grouped(APIAuthenticationMiddleware(), User.guardMiddleware())
    try protectedAPI.register(collection: BoardController())
    try protectedAPI.register(collection: BoardResourceController())
    try protectedAPI.register(collection: BoardConfigurationController())
    try protectedAPI.register(collection: TaskController())
    try protectedAPI.register(collection: TaskResourceController())
    try protectedAPI.register(collection: AttachmentController())
}

private struct HealthResponse: Content {
    let status: String
    let service: String
}

private struct APIIndexResponse: Content {
    let name: String
    let version: String
    let authentication: String
    let apiKeys: String
    let boards: String
    let tasks: String
    let taskSearch: String
}
