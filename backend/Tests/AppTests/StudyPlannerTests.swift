@testable import App
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Weekly study planner")
struct StudyPlannerTests {
    @Test("The planner builds a Monday through Sunday agenda")
    func buildsCurrentWeek() throws {
        let courseID = UUID()
        let course = Board(id: courseID, name: "MATH 241", slug: "math-241")
        course.$tasks.value = []
        let navigation = try BoardNavigationContext(
            board: course,
            firstViewID: nil,
            courseColorClass: "course-blue"
        )
        let monday = try #require(studyDate("2026-08-03"))
        let wednesday = try #require(studyDate("2026-08-05"))
        let dueTask = try studyTaskContext(
            board: course,
            title: "Finish calculus problem set",
            dueAt: wednesday,
            priority: .high
        )
        let unscheduledTask = try studyTaskContext(
            board: course,
            title: "Review flashcards",
            dueAt: nil,
            priority: .low
        )

        let planner = OverviewPageContext(
            tasks: [dueTask, unscheduledTask],
            courses: [navigation],
            selectedCourseID: nil,
            referenceDate: monday
        )

        #expect(planner.weekLabel == "August 3–9")
        #expect(planner.days.count == 7)
        #expect(planner.days[0].weekdayLabel == "Mon")
        #expect(planner.days[0].isToday)
        #expect(planner.days[2].assignments.first?.title == "Finish calculus problem set")
        #expect(planner.days[2].assignments.first?.typeName == "Problem Set")
        #expect(planner.days[2].workloadLabel == "Heavy")
        #expect(planner.days.reduce(0) { $0 + $1.assignmentCount } == 1)
        #expect(planner.unscheduledAssignmentCount == 1)
    }

    @Test("The overview renders course planning controls")
    func overviewRendersPlanner() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let response = try await app.testing().sendRequest(
                .GET,
                "app",
                headers: ["Cookie": session.cookie]
            )

            #expect(response.status == .ok)
            expectContains(response.body.string, "This week")
            expectContains(response.body.string, "Courses")
            expectContains(response.body.string, "Plan this week")
            expectContains(response.body.string, "Add assignment")
            expectContains(response.body.string, "My board")
        }
    }
}

private func studyDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private func studyTaskContext(
    board: Board,
    title: String,
    dueAt: Date?,
    priority: TaskPriority
) throws -> TaskCardContext {
    let task = Task(
        id: UUID(),
        publicID: String(UUID().uuidString.prefix(6)).lowercased(),
        boardID: try board.requireID(),
        title: title,
        priority: priority,
        position: 1_000,
        dueAt: dueAt
    )
    task.$board.value = board
    return try TaskCardContext(task: task, assignee: nil, board: board)
}
