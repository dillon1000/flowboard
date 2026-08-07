@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Study settings")
struct StudySettingsTests {
    @Test("Availability and bulk estimates persist together")
    func persistsPlanningInputs() async throws {
        try await withApp(configure: configure) { app in
            let registered = try await register(on: app)
            let task = Task(
                boardID: registered.boardID,
                title: "Read chapter 4",
                position: 1_000,
                dueAt: Date().addingTimeInterval(86_400),
                creatorID: registered.userID
            )
            try await task.create(on: app.db)

            let defaultSettings = try await app.testing().sendRequest(
                .GET,
                "api/v1/study-settings",
                headers: ["Cookie": registered.cookie]
            )
            #expect(defaultSettings.status == .ok)
            #expect(
                try defaultSettings.content.decode(StudySettingsResponse.self)
                    .estimatePresets.first?.name == "Reading"
            )

            let capacities = StudySettings.defaultWeekdayCapacityMinutes.merging(
                ["monday": 75],
                uniquingKeysWith: { _, new in new }
            )
            let savedSettings = try await app.testing().sendRequest(
                .PUT,
                "api/v1/study-settings",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        StudySettingsRequest(
                            weekdayCapacityMinutes: capacities,
                            blockedDates: ["2026-08-10"],
                            recurringCommitments: [
                                StudyRecurringCommitment(
                                    id: "chem-class",
                                    title: "Chemistry",
                                    kind: "class",
                                    weekdays: [1, 3],
                                    startTime: "10:00",
                                    endTime: "11:15"
                                ),
                            ],
                            calendarConflicts: [],
                            estimatePresets: StudyEstimatePreset.defaults,
                            timeZoneConfirmed: true,
                            availabilityConfigured: true
                        )
                    )
                }
            )
            #expect(savedSettings.status == .ok)
            #expect(
                try savedSettings.content.decode(StudySettingsResponse.self)
                    .weekdayCapacityMinutes["monday"] == 75
            )

            let estimateResponse = try await app.testing().sendRequest(
                .POST,
                "api/v1/study-settings/estimates",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        BulkTaskEstimatesRequest(
                            estimates: [
                                BulkTaskEstimate(
                                    taskID: try task.requireID(),
                                    estimatedMinutes: 45
                                ),
                            ],
                            estimatePresets: nil
                        )
                    )
                }
            )
            #expect(estimateResponse.status == .ok)
            #expect(
                try estimateResponse.content.decode(BulkTaskEstimatesResponse.self)
                    .updatedTaskCount == 1
            )
            #expect(try await Task.find(task.requireID(), on: app.db)?.estimatedMinutes == 45)
        }
    }

    @Test("Bulk estimates require edit permission")
    func bulkEstimatesRequireEditPermission() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let viewer = try await register(on: app)
            try await BoardMember(
                boardID: owner.boardID,
                userID: viewer.userID,
                role: .viewer
            ).create(on: app.db)
            let task = Task(
                boardID: owner.boardID,
                title: "Read chapter 4",
                position: 1_000,
                estimatedMinutes: 30,
                creatorID: owner.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()

            let response = try await app.testing().sendRequest(
                .POST,
                "api/v1/study-settings/estimates",
                headers: ["Cookie": viewer.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        BulkTaskEstimatesRequest(
                            estimates: [BulkTaskEstimate(taskID: taskID, estimatedMinutes: 45)],
                            estimatePresets: nil
                        )
                    )
                }
            )

            #expect(response.status == .notFound)
            #expect(try await Task.find(taskID, on: app.db)?.estimatedMinutes == 30)
        }
    }
}
