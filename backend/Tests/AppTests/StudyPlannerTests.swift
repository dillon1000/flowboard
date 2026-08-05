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
            priority: .high,
            estimatedMinutes: 180
        )
        let unscheduledTask = try studyTaskContext(
            board: course,
            title: "Review flashcards",
            dueAt: nil,
            priority: .low,
            estimatedMinutes: nil
        )
        let focusTask = try studyTaskContext(
            board: course,
            title: "Outline lab report",
            dueAt: try #require(studyDate("2026-08-07")),
            priority: .medium,
            estimatedMinutes: 45,
            startAt: monday
        )
        let plannedOnDeadline = try studyTaskContext(
            board: course,
            title: "Prepare seminar notes",
            dueAt: monday,
            priority: .medium,
            estimatedMinutes: 180,
            startAt: monday
        )
        let studySession = StudySession(
            id: UUID(),
            taskID: dueTask.id,
            userID: UUID(),
            scheduledDate: "2026-08-04",
            plannedMinutes: 60
        )

        let planner = OverviewPageContext(
            tasks: [dueTask, unscheduledTask, focusTask, plannedOnDeadline],
            courses: [navigation],
            selectedCourseID: nil,
            studySessions: [studySession],
            referenceDate: monday
        )

        #expect(planner.weekLabel == "August 3–9")
        #expect(planner.days.count == 7)
        #expect(planner.days[0].weekdayLabel == "Mon")
        #expect(planner.days[0].isToday)
        #expect(planner.days[0].focusBlocks.first?.title == "Outline lab report")
        #expect(planner.days[0].assignments.first?.title == "Prepare seminar notes")
        #expect(planner.days[0].workloadMinutes == 225)
        #expect(planner.days[1].focusBlocks.first?.title == "Finish calculus problem set")
        #expect(planner.days[1].workloadMinutes == 60)
        #expect(planner.days[2].assignments.first?.title == "Finish calculus problem set")
        #expect(planner.days[2].assignments.first?.typeName == "Problem Set")
        #expect(planner.days[2].workloadLabel == "Unplanned")
        #expect(planner.days[2].workloadMinutes == 0)
        #expect(planner.days.reduce(0) { $0 + $1.assignmentCount } == 3)
        #expect(planner.planCandidates.first?.remainingMinutes == 120)
        #expect(planner.unscheduledAssignmentCount == 1)
        #expect(planner.studyStreakDays == 1)
    }

    @Test("Local dates do not advance at the UTC boundary")
    func respectsLocalDateBoundaries() throws {
        let utcBoundary = try #require(ISO8601DateFormatter().date(from: "2026-08-03T00:30:00Z"))

        let chicagoPlanner = OverviewPageContext(
            tasks: [],
            courses: [],
            selectedCourseID: nil,
            timeZoneIdentifier: "America/Chicago",
            referenceDate: utcBoundary
        )
        let tokyoPlanner = OverviewPageContext(
            tasks: [],
            courses: [],
            selectedCourseID: nil,
            timeZoneIdentifier: "Asia/Tokyo",
            referenceDate: utcBoundary
        )
        let chicagoSemester = SemesterPageContext(
            tasks: [],
            courses: [],
            timeZoneIdentifier: "America/Chicago",
            referenceDate: utcBoundary
        )

        #expect(chicagoPlanner.weekLabel == "Jul 27–Aug 2")
        #expect(chicagoPlanner.days[6].isToday)
        #expect(tokyoPlanner.weekLabel == "August 3–9")
        #expect(tokyoPlanner.days[0].isToday)
        #expect(chicagoSemester.weeks[0].label == "Jul 27–Aug 2")
    }

    @Test("The overview API returns course planning data")
    func overviewReturnsPlannerData() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let response = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace",
                headers: ["Cookie": session.cookie]
            )

            #expect(response.status == .ok)
            expectContains(response.body.string, #""pageTitle":"This week""#)
            expectContains(response.body.string, #""weekLabel":""#)
            expectContains(response.body.string, #""courseFilters""#)
            expectContains(response.body.string, #""days""#)
            expectContains(response.body.string, #""name":"My board""#)
        }
    }

    @Test("The semester horizon groups saved deadlines by week")
    func groupsSemesterDeadlines() throws {
        let courseID = UUID()
        let course = Board(id: courseID, name: "CHEM 201", slug: "chem-201")
        course.$tasks.value = []
        let navigation = try BoardNavigationContext(
            board: course,
            firstViewID: nil,
            courseColorClass: "course-green"
        )
        let firstWeek = try #require(studyDate("2026-08-03"))
        let deadline = try studyTaskContext(
            board: course,
            title: "Prepare lab report",
            dueAt: try #require(studyDate("2026-08-06")),
            priority: .high,
            estimatedMinutes: 480
        )

        let horizon = SemesterPageContext(
            tasks: [deadline],
            courses: [navigation],
            referenceDate: firstWeek
        )

        #expect(horizon.weeks.count == 16)
        #expect(horizon.scheduledAssignmentCount == 1)
        #expect(horizon.highLoadWeekCount == 1)
        #expect(horizon.weeks[0].assignments.first?.title == "Prepare lab report")
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
    priority: TaskPriority,
    estimatedMinutes: Int?,
    startAt: Date? = nil
) throws -> TaskCardContext {
    let task = Task(
        id: UUID(),
        publicID: String(UUID().uuidString.prefix(6)).lowercased(),
        boardID: try board.requireID(),
        title: title,
        priority: priority,
        position: 1_000,
        startAt: startAt,
        dueAt: dueAt,
        estimatedMinutes: estimatedMinutes
    )
    task.$board.value = board
    return try TaskCardContext(task: task, assignee: nil, board: board)
}
