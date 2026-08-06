@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Study sessions")
struct StudySessionTests {
    @Test("The planner splits estimates and is idempotent")
    func splitsAcrossAvailableDays() throws {
        let taskID = UUID()
        let monday = try #require(studySessionDate("2026-08-03"))
        let tasks = [
            StudyPlanningTask(
                id: taskID,
                dueDate: "2026-08-05",
                estimatedMinutes: 180,
                priority: "high"
            ),
        ]
        let firstPlan = StudyPlanningService.plan(
            tasks: tasks,
            sessions: [],
            dailyLimitMinutes: 120,
            timeZoneIdentifier: "America/Chicago",
            referenceDate: monday
        )

        #expect(firstPlan.allocations.count == 3)
        #expect(firstPlan.allocations.map(\.scheduledDate) == [
            "2026-08-03", "2026-08-04", "2026-08-05",
        ])
        #expect(firstPlan.allocations.map(\.plannedMinutes) == [60, 60, 60])
        #expect(firstPlan.remainingMinutes == 0)

        let secondPlan = StudyPlanningService.plan(
            tasks: tasks,
            sessions: firstPlan.allocations.map {
                StudyPlanningSession(
                    taskID: $0.taskID,
                    scheduledDate: $0.scheduledDate,
                    plannedMinutes: $0.plannedMinutes,
                    state: .planned,
                    actualMinutes: nil
                )
            },
            dailyLimitMinutes: 120,
            timeZoneIdentifier: "America/Chicago",
            referenceDate: monday
        )
        #expect(secondPlan.allocations.isEmpty)
        #expect(secondPlan.remainingMinutes == 0)
    }

    @Test("Study session routes manage and automatically plan work")
    func lifecycleAndAutoPlan() async throws {
        try await withApp(configure: configure) { app in
            let registered = try await register(on: app)
            let dueAt = Date().addingTimeInterval(7 * 24 * 60 * 60)
            let task = Task(
                boardID: registered.boardID,
                title: "Prepare final presentation",
                position: 1_000,
                dueAt: dueAt,
                estimatedMinutes: 90,
                creatorID: registered.userID
            )
            try await task.create(on: app.db)
            let taskID = try task.requireID()
            let scheduledDate = inputDate(Date())

            let created = try await app.testing().sendRequest(
                .POST,
                "api/v1/tasks/\(taskID)/study-sessions",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreateStudySessionRequest(
                            scheduledDate: scheduledDate,
                            plannedMinutes: 30
                        )
                    )
                }
            )
            #expect(created.status == .created)
            let createdSession = try created.content.decode(StudySessionResponse.self)
            #expect(createdSession.state == .planned)

            let updated = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/study-sessions/\(createdSession.id)",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        UpdateStudySessionRequest(scheduledDate: nil, plannedMinutes: 45)
                    )
                }
            )
            #expect(updated.status == .ok)
            #expect(try updated.content.decode(StudySessionResponse.self).plannedMinutes == 45)

            let completed = try await app.testing().sendRequest(
                .POST,
                "api/v1/study-sessions/\(createdSession.id)/complete",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(CompleteStudySessionRequest(actualMinutes: 40))
                }
            )
            #expect(completed.status == .ok)
            #expect(try completed.content.decode(StudySessionResponse.self).state == .completed)
            #expect(try completed.content.decode(StudySessionResponse.self).actualMinutes == 40)

            let listed = try await app.testing().sendRequest(
                .GET,
                "api/v1/tasks/\(taskID)/study-sessions",
                headers: ["Cookie": registered.cookie]
            )
            #expect(try listed.content.decode([StudySessionResponse].self).count == 1)

            let deleted = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/study-sessions/\(createdSession.id)",
                headers: ["Cookie": registered.cookie]
            )
            #expect(deleted.status == .noContent)

            let firstPlan = try await app.testing().sendRequest(
                .POST,
                "api/v1/study-sessions/plan",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        AutoPlanStudySessionsRequest(dailyLimitMinutes: 1_440, courseID: nil)
                    )
                }
            )
            #expect(firstPlan.status == .ok)
            let firstResult = try firstPlan.content.decode(AutoPlanStudySessionsResponse.self)
            #expect(firstResult.plannedMinutes == 90)
            #expect(firstResult.remainingMinutes == 0)

            let secondPlan = try await app.testing().sendRequest(
                .POST,
                "api/v1/study-sessions/plan",
                headers: ["Cookie": registered.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        AutoPlanStudySessionsRequest(dailyLimitMinutes: 1_440, courseID: nil)
                    )
                }
            )
            #expect(secondPlan.status == .ok)
            #expect(try secondPlan.content.decode(AutoPlanStudySessionsResponse.self).plannedMinutes == 0)
            #expect(
                try await StudySession.query(on: app.db)
                    .filter(\.$task.$id == taskID)
                    .filter(\.$user.$id == registered.userID)
                    .all()
                    .reduce(0) { $0 + $1.plannedMinutes } == 90
            )
        }
    }
}

private func studySessionDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/Chicago")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}
