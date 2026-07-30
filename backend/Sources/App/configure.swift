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
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .any(allowedOrigins),
        allowedMethods: [.GET, .POST, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin],
        allowCredentials: true
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    // Leaf renders the account pages and the authenticated Svelte shell. File
    // middleware serves the frontend bundle created by `pnpm build`.
    app.views.use(.leaf)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Sessions use Fluent so login survives server restarts and works across
    // multiple application processes that share the same database.
    app.sessions.use(.fluent)
    app.sessions.configuration.cookieName = "flowboard-session"
    app.sessions.configuration.cookieFactory = { sessionID in
        .init(
            string: sessionID.string,
            expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 14),
            path: "/",
            isSecure: app.environment == .production,
            isHTTPOnly: true,
            sameSite: .strict
        )
    }
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(User.sessionAuthenticator())
    app.middleware.use(CSRFMiddleware())

    app.migrations.add(CreateUser())
    app.migrations.add(CreateBoard())
    app.migrations.add(AddBoardOwner())
    app.migrations.add(CreateTask())
    app.migrations.add(ExpandWorkspace())
    app.migrations.add(CreateWorkspaceFeatures())
    app.migrations.add(BackfillBoardViews())
    app.migrations.add(SessionRecord.migration)

    if app.environment == .development || app.environment == .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
