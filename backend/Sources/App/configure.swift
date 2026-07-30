import Fluent
import FluentSQLiteDriver
import Vapor

/// Configures the database, middleware, migrations, and routes for one application process.
///
/// The database is in memory during tests. Other environments use `DATABASE_PATH`, or
/// `db.sqlite` when the variable is absent. Development and test processes migrate on
/// startup so a new checkout is immediately usable. Production migrations stay explicit.
public func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let databasePath = Environment.get("DATABASE_PATH") ?? "db.sqlite"
        app.databases.use(.sqlite(.file(databasePath)), as: .sqlite)
    }

    let allowedOrigin = Environment.get("CORS_ORIGIN") ?? "http://localhost:5173"
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .custom(allowedOrigin),
        allowedMethods: [.GET, .POST, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration), at: .beginning)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    app.migrations.add(CreateBoard())
    app.migrations.add(CreateTask())
    app.migrations.add(SeedWorkspace())

    if app.environment == .development || app.environment == .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
