import Foundation

/// A sixteen-week course horizon built from existing assignment deadlines. It
/// reports only saved dates and estimates, so students can trust what they see.
struct SemesterPageContext: Encodable {
    let rangeLabel: String
    let weeks: [SemesterWeekContext]
    let scheduledAssignmentCount: Int
    let highLoadWeekCount: Int
    let undatedAssignmentCount: Int
    let hasUndatedAssignments: Bool

    init(
        tasks: [TaskCardContext],
        courses: [BoardNavigationContext],
        referenceDate: Date = Date()
    ) {
        let calendar = semesterCalendar()
        let today = calendar.startOfDay(for: referenceDate)
        let weekdayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let firstWeek = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let weekStarts = (0..<16).compactMap { calendar.date(byAdding: .day, value: $0 * 7, to: firstWeek) }
        let courseColors = Dictionary(
            uniqueKeysWithValues: courses.filter { !$0.isArchived }.map { ($0.id, $0.courseColorClass) }
        )
        let activeTasks = tasks.filter { !semesterTaskIsCompleted($0) }
        let scheduledTasks = activeTasks.compactMap { task -> (TaskCardContext, Date)? in
            guard let dueDate = semesterDate(task.dueInput) else { return nil }
            return (task, dueDate)
        }
        var renderedWeeks: [SemesterWeekContext] = []
        for start in weekStarts {
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let tasksInWeek = scheduledTasks.filter { pair in
                pair.1 >= start && pair.1 < end
            }
            let assignments = tasksInWeek.map { pair in
                SemesterAssignmentContext(
                    task: pair.0,
                    courseColorClass: courseColors[pair.0.boardID] ?? "course-blue"
                )
            }
            renderedWeeks.append(
                SemesterWeekContext(
                    start: start,
                    assignments: assignments.sorted { $0.dueInput < $1.dueInput }
                )
            )
        }
        self.weeks = renderedWeeks
        let finalWeek = calendar.date(byAdding: .day, value: 6, to: weekStarts.last ?? firstWeek) ?? firstWeek
        let firstLabel = semesterDateLabel(firstWeek, format: "MMM d")
        let finalLabel = semesterDateLabel(finalWeek, format: "MMM d, yyyy")
        self.rangeLabel = firstLabel + " – " + finalLabel
        self.scheduledAssignmentCount = renderedWeeks.reduce(0) { $0 + $1.assignmentCount }
        self.highLoadWeekCount = renderedWeeks.filter(\.isHighLoad).count
        self.undatedAssignmentCount = activeTasks.filter { !$0.hasDueDate }.count
        self.hasUndatedAssignments = undatedAssignmentCount > 0
    }
}

struct SemesterWeekContext: Encodable {
    let label: String
    let assignments: [SemesterAssignmentContext]
    let assignmentCount: Int
    let workloadLabel: String
    let workloadClass: String
    let isHighLoad: Bool

    init(start: Date, assignments: [SemesterAssignmentContext]) {
        self.label = semesterWeekLabel(start: start, calendar: semesterCalendar())
        self.assignments = assignments
        self.assignmentCount = assignments.count
        let estimatedMinutes = assignments.reduce(0) { $0 + $1.estimatedMinutes }
        let hasMissingEstimate = assignments.contains { !$0.hasEstimate }
        if hasMissingEstimate && !assignments.isEmpty {
            self.workloadLabel = "Needs estimates"
            self.workloadClass = "needs-estimates"
            self.isHighLoad = false
        } else if estimatedMinutes >= 8 * 60 {
            self.workloadLabel = "High load · " + displayDuration(estimatedMinutes)
            self.workloadClass = "high"
            self.isHighLoad = true
        } else if estimatedMinutes > 0 {
            self.workloadLabel = displayDuration(estimatedMinutes) + " planned"
            self.workloadClass = "planned"
            self.isHighLoad = false
        } else {
            self.workloadLabel = "Open week"
            self.workloadClass = "open"
            self.isHighLoad = false
        }
    }
}

struct SemesterAssignmentContext: Encodable {
    let href: String
    let title: String
    let courseName: String
    let courseColorClass: String
    let dueInput: String
    let dueLabel: String
    let estimatedMinutes: Int
    let effortLabel: String
    let hasEstimate: Bool

    init(task: TaskCardContext, courseColorClass: String) {
        self.href = task.href
        self.title = task.title
        self.courseName = task.boardName
        self.courseColorClass = courseColorClass
        self.dueInput = task.dueInput
        self.dueLabel = task.dueDisplay
        self.estimatedMinutes = task.estimatedMinutes
        self.effortLabel = task.estimatedDisplay
        self.hasEstimate = task.hasEstimate
    }
}

private func semesterCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}

private func semesterDate(_ value: String) -> Date? {
    guard !value.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private func semesterDateLabel(_ date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter.string(from: date)
}

private func semesterWeekLabel(start: Date, calendar: Calendar) -> String {
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    let startMonth = calendar.component(.month, from: start)
    let endMonth = calendar.component(.month, from: end)
    if startMonth == endMonth {
        return semesterDateLabel(start, format: "MMMM d") + "–" + semesterDateLabel(end, format: "d")
    }
    return semesterDateLabel(start, format: "MMM d") + "–" + semesterDateLabel(end, format: "MMM d")
}

private func semesterTaskIsCompleted(_ task: TaskCardContext) -> Bool {
    task.completionStatuses.split(separator: ",").contains(Substring(task.statusValue))
}
