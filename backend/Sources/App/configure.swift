import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

/// Configures the database, middleware, migrations, and routes for one application process.
///
/// The database is in memory during tests. Other environments use `DATABASE_PATH`, or
/// `db.sqlite` when the variable is absent. Development and test processes migrate on
/// startup so a new checkout is immediately usable. Production migrations stay explicit.
public func configure(_ app: Application) async throws {
    // Browser forms can carry an attachment or board export. Route handlers apply
    // their own smaller file limits after Vapor rejects bodies above 10 MB.
    app.routes.defaultMaxBodySize = "10mb"
    app.oauthConfiguration = try OAuthConfiguration.fromEnvironment()

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let databasePath = Environment.get("DATABASE_PATH") ?? "db.sqlite"
        app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
    }

    // CORS_ORIGIN accepts a comma-separated allowlist. Both local hostnames work by
    // default because Vite can advertise either one based on its bind address.
    let allowedOrigins = (Environment.get("CORS_ORIGIN")
        ?? "http://localhost:5173,http://127.0.0.1:5173")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    // These values identify the service in response headers. Deployments can
    // override either value without rebuilding the application.
    let serverName = Environment.get("SERVER_NAME") ?? "flowboard-server"
    let serverVersion = Environment.get("SERVER_VERSION") ?? "0.1.0"
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .any(allowedOrigins),
        allowedMethods: [.GET, .POST, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin],
        allowCredentials: true,
        exposedHeaders: [
            .flowboardServerName,
            .flowboardServerTime,
            .flowboardServerVersion,
        ]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(
        ServerHeadersMiddleware(serverName: serverName, serverVersion: serverVersion),
        at: .beginning
    )

    // Leaf renders every browser page. File middleware serves the Hotwire,
    // Stimulus, and design assets created by `pnpm build`.
    app.views.use(.leaf)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Sessions use Fluent so login survives server restarts and works across
    // multiple application processes that share the same database. SameSite=Lax
    // sends the session on the provider's top-level OAuth callback.
    app.sessions.use(.fluent)
    app.sessions.configuration.cookieName = "flowboard-session"
    app.sessions.configuration.cookieFactory = { sessionID in
        .init(
            string: sessionID.string,
            expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 14),
            path: "/",
            isSecure: app.environment == .production,
            isHTTPOnly: true,
            sameSite: .lax
        )
    }
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(User.sessionAuthenticator())
    app.middleware.use(CSRFMiddleware())

    app.migrations.add(CreateUser())
    app.migrations.add(CreateOAuthAccount())
    app.migrations.add(AddUserProfilePicture())
    app.migrations.add(CreateBoard())
    app.migrations.add(AddBoardOwner())
    app.migrations.add(AddBoardTaskDefinitions())
    app.migrations.add(CreateTask())
    app.migrations.add(ExpandWorkspace())
    app.migrations.add(CreateWorkspaceFeatures())
    app.migrations.add(BackfillBoardViews())
    app.migrations.add(CreateTaskFollowers())
    app.migrations.add(AddTaskCreator())
    app.migrations.add(SessionRecord.migration)

    if app.environment == .development || app.environment == .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
