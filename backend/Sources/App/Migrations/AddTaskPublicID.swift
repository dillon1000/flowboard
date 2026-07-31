import Fluent
import Foundation

/// Uses only the columns that exist while this migration runs. The main Task model
/// can continue to evolve without making a fresh database fail on an older schema.
private final class TaskPublicIDBackfill: Model, @unchecked Sendable {
    static let schema = Task.schema

    @ID(key: .id)
    var id: UUID?

    @OptionalField(key: "public_id")
    var publicID: String?

    init() {}
}

/// Adds the stable six-character key at the end of each public task URL. The title
/// stays presentational, so renaming a task does not invalidate an existing link.
struct AddTaskPublicID: AsyncMigration {
    private let indexName = "uq_tasks_public_id"

    func prepare(on database: any Database) async throws {
        // SQLite cannot add a required unique column to a populated table. Add the
        // nullable column, backfill every row, then enforce uniqueness with an index.
        try await database.schema(Task.schema)
            .field("public_id", .string)
            .update()

        let tasks = try await TaskPublicIDBackfill.query(on: database).all()
        var assignedIDs = Set(tasks.compactMap(\.publicID))
        for task in tasks where task.publicID == nil {
            var publicID = Task.randomPublicID()
            while assignedIDs.contains(publicID) {
                publicID = Task.randomPublicID()
            }
            assignedIDs.insert(publicID)
            task.publicID = publicID
            try await task.update(on: database)
        }

        let index = TaskPublicIDBackfill.query(on: database)
        index.query.action = .custom(
            "CREATE UNIQUE INDEX \"\(indexName)\" ON \"\(Task.schema)\" (\"public_id\" COLLATE NOCASE)"
        )
        try await index.run().get()
    }

    func revert(on database: any Database) async throws {
        let index = TaskPublicIDBackfill.query(on: database)
        index.query.action = .custom("DROP INDEX IF EXISTS \"\(indexName)\"")
        try await index.run().get()
        try await database.schema(Task.schema)
            .deleteField("public_id")
            .update()
    }
}
