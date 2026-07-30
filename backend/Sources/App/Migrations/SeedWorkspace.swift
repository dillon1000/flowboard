import Fluent
import Foundation

/// Adds a deterministic starter board so the frontend has useful content on first run.
/// Reverting the migration removes only these fixed identifiers.
struct SeedWorkspace: AsyncMigration {
    static let boardID = UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE001")!

    private let taskIDs = [
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE101")!,
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE102")!,
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE103")!,
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE104")!,
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE105")!,
        UUID(uuidString: "0F2B7A0A-96DC-4D5E-874B-7C9DEAAAE106")!
    ]

    func prepare(on database: any Database) async throws {
        try await Board(id: Self.boardID, name: "Launch week", slug: "launch-week").create(on: database)

        let tasks = [
            Task(
                id: taskIDs[0],
                boardID: Self.boardID,
                title: "Map the first-run experience",
                description: "Reduce the path from empty account to the first useful board.",
                status: .backlog,
                priority: .high,
                position: 1_000,
                labels: ["Product", "UX"]
            ),
            Task(
                id: taskIDs[1],
                boardID: Self.boardID,
                title: "Write the launch checklist",
                status: .backlog,
                priority: .medium,
                position: 2_000,
                labels: ["Ops"]
            ),
            Task(
                id: taskIDs[2],
                boardID: Self.boardID,
                title: "Connect usage events",
                description: "Track board created, task moved, and task completed.",
                status: .inProgress,
                priority: .urgent,
                position: 1_000,
                labels: ["Data", "API"]
            ),
            Task(
                id: taskIDs[3],
                boardID: Self.boardID,
                title: "Polish command menu states",
                status: .inProgress,
                priority: .medium,
                position: 2_000,
                labels: ["Frontend"]
            ),
            Task(
                id: taskIDs[4],
                boardID: Self.boardID,
                title: "Review billing copy",
                status: .review,
                priority: .high,
                position: 1_000,
                labels: ["Copy"]
            ),
            Task(
                id: taskIDs[5],
                boardID: Self.boardID,
                title: "Set the release branch rules",
                status: .done,
                priority: .low,
                position: 1_000,
                labels: ["Git"]
            )
        ]

        for task in tasks {
            try await task.create(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        try await Task.query(on: database).filter(\.$id ~~ taskIDs).delete()
        try await Board.query(on: database).filter(\.$id == Self.boardID).delete()
    }
}
