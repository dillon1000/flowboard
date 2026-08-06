import Foundation

enum AppPageKind {
    case overview
    case semester
    case board
    case tasks
    case archivedTasks
    case taskDetail
    case settings
    case availabilitySettings
    case apiKeys
    case integrations
    case boardSettings
}

struct AppPageContext: Encodable {
    let common: CommonPageContext
    let pageTitle: String
    let documentTitle: String
    let isOverview: Bool
    let isSemester: Bool
    let isBoard: Bool
    let isTasks: Bool
    let isActiveTasks: Bool
    let isArchivedTasks: Bool
    let isTaskDetail: Bool
    let isSettings: Bool
    let isProfileSettings: Bool
    let isAvailabilitySettings: Bool
    let isAPIKeys: Bool
    let isIntegrations: Bool
    let isBoardSettings: Bool
    let overview: OverviewPageContext?
    let semester: SemesterPageContext?
    let board: BoardPageContext?
    let tasks: TasksPageContext?
    let taskDetail: TaskDetailPageContext?
    let settings: SettingsPageContext?
    let availabilitySettings: StudySettingsResponse?
    let apiKeys: APIKeysPageContext?
    let integrations: CanvasIntegrationsPageContext?
    let boardSettings: BoardSettingsPageContext?

    init(
        common: CommonPageContext,
        pageTitle: String,
        pageKind: AppPageKind,
        overview: OverviewPageContext?,
        semester: SemesterPageContext?,
        board: BoardPageContext?,
        tasks: TasksPageContext?,
        taskDetail: TaskDetailPageContext?,
        settings: SettingsPageContext?,
        availabilitySettings: StudySettingsResponse?,
        apiKeys: APIKeysPageContext?,
        integrations: CanvasIntegrationsPageContext?,
        boardSettings: BoardSettingsPageContext?
    ) {
        self.common = common
        self.pageTitle = pageTitle
        self.documentTitle = "\(pageTitle) · Flowboard"
        self.isOverview = pageKind == .overview
        self.isSemester = pageKind == .semester
        self.isBoard = pageKind == .board
        self.isTasks = pageKind == .tasks || pageKind == .archivedTasks
        self.isActiveTasks = pageKind == .tasks
        self.isArchivedTasks = pageKind == .archivedTasks
        self.isTaskDetail = pageKind == .taskDetail
        self.isSettings = pageKind == .settings || pageKind == .availabilitySettings || pageKind == .apiKeys || pageKind == .integrations
        self.isProfileSettings = pageKind == .settings
        self.isAvailabilitySettings = pageKind == .availabilitySettings
        self.isAPIKeys = pageKind == .apiKeys
        self.isIntegrations = pageKind == .integrations
        self.isBoardSettings = pageKind == .boardSettings
        self.overview = overview
        self.semester = semester
        self.board = board
        self.tasks = tasks
        self.taskDetail = taskDetail
        self.settings = settings
        self.availabilitySettings = availabilitySettings
        self.apiKeys = apiKeys
        self.integrations = integrations
        self.boardSettings = boardSettings
    }
}

struct CommonPageContext: Encodable {
    let userName: String
    let userEmail: String
    let userTimeZone: String
    let dailyBriefEnabled: Bool
    let weeklyPlanningPromptEnabled: Bool
    let planningEmailHour: Int
    let userAvatar: AvatarContext
    let boards: [BoardNavigationContext]
    let searchAssignments: [SearchAssignmentContext]
}

/// Carries only the assignment fields needed by the global finder. Keeping this
/// payload small lets every page offer the same results without another request.
struct SearchAssignmentContext: Encodable {
    let id: UUID
    let title: String
    let courseName: String
    let href: String
    let searchText: String

    init(task: Task, courseName: String) throws {
        self.id = try task.requireID()
        self.title = task.title
        self.courseName = courseName
        self.href = task.browserPath
        self.searchText = ([task.description ?? ""] + task.labels).joined(separator: " ")
    }
}

/// Supplies one image-or-initials choice wherever a user identity appears.
/// OAuth URLs are validated before storage, so clients only select the display.
struct AvatarContext: Encodable {
    let initials: String
    let profilePictureURL: String
    let hasProfilePicture: Bool

    init(user: User) {
        self.initials = makeInitials(for: user.name)
        self.profilePictureURL = user.profilePictureURL ?? ""
        self.hasProfilePicture = user.profilePictureURL != nil
    }
}

struct BoardNavigationContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let href: String
    let courseColorClass: String
    let taskCount: Int
    let completedCount: Int
    let isArchived: Bool
    let isCanvasLinked: Bool
    let canvasURL: String
    let canvasGradeDisplay: String

    init(
        board: Board,
        firstViewID: UUID?,
        courseColorClass: String,
        canvasLink: CanvasCourseLink? = nil
    ) throws {
        let id = try board.requireID()
        self.id = id
        self.name = board.name
        self.description = board.description ?? "No description"
        self.href = if let firstViewID {
            "/app/boards/\(id)/views/\(firstViewID)"
        } else {
            "/app/boards/\(id)"
        }
        self.courseColorClass = courseColorClass
        self.taskCount = board.tasks.filter { !$0.isArchived }.count
        self.completedCount = board.tasks.filter {
            !$0.isArchived && board.isCompleted($0.status)
        }.count
        self.isArchived = board.isArchived
        self.isCanvasLinked = canvasLink != nil
        self.canvasURL = canvasLink?.canvasCourseURL ?? ""
        self.canvasGradeDisplay = canvasCourseGradeDisplay(link: canvasLink)
    }
}

struct OverviewPageContext: Encodable {
    let weekLabel: String
    let courseFilters: [StudyCourseContext]
    let isAllCoursesSelected: Bool
    let defaultCourseID: String
    let defaultCourseName: String
    let hasCourses: Bool
    let returnHref: String
    let days: [StudyDayContext]
    let workloadDays: [StudyWorkloadDayContext]
    let balanceName: String
    let balanceDescription: String
    let unscheduledAssignmentCount: Int
    let hasUnscheduledAssignments: Bool
    let unestimatedAssignmentCount: Int
    let hasUnestimatedAssignments: Bool
    let planCandidates: [StudyPlanCandidateContext]
    let hasPlanCandidates: Bool
    let unplannedFocusCount: Int
    let hasUnplannedFocus: Bool
    let studyStreakDays: Int
    let studySettings: StudySettingsResponse
    let recovery: StudyRecoveryContext
    let estimationInbox: [StudyEstimateInboxItemContext]
    let hasEstimationInbox: Bool
    let onboarding: StudyOnboardingContext

    init(
        tasks: [TaskCardContext],
        courses: [BoardNavigationContext],
        selectedCourseID: UUID?,
        studySessions: [StudySession] = [],
        settings: StudySettings? = nil,
        hasCanvasConnection: Bool = false,
        timeZoneIdentifier: String = "UTC",
        referenceDate: Date = Date()
    ) {
        let calendar = planningCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: referenceDate)
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let weekDates = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
        let activeCourses = courses.filter { !$0.isArchived }
        let courseColors = Dictionary(
            uniqueKeysWithValues: activeCourses.map { ($0.id, $0.courseColorClass) }
        )
        let taskContexts = tasks.filter { task in
            selectedCourseID == nil || task.boardID == selectedCourseID
        }
        let activeTaskContexts = taskContexts.filter { !studyTaskIsCompleted($0) }
        let taskByID = Dictionary(uniqueKeysWithValues: taskContexts.map { ($0.id, $0) })
        let activeTaskByID = Dictionary(uniqueKeysWithValues: activeTaskContexts.map { ($0.id, $0) })
        let taskSessions = studySessions.filter { taskByID[$0.$task.id] != nil }
        let activeTaskSessions = taskSessions.filter { activeTaskByID[$0.$task.id] != nil }
        let sessionTaskIDs = Set(activeTaskSessions.map(\.$task.id))
        let availability = StudyAvailability(settings: settings)
        let settingsContext = StudySettingsResponse(settings: settings)

        self.weekLabel = studyWeekLabel(start: weekStart, calendar: calendar)
        self.courseFilters = activeCourses.map {
            StudyCourseContext(course: $0, tasks: tasks, selectedCourseID: selectedCourseID)
        }
        self.isAllCoursesSelected = selectedCourseID == nil
        let defaultCourse = activeCourses.first {
            $0.id == selectedCourseID
        } ?? activeCourses.first
        self.defaultCourseID = defaultCourse?.id.uuidString ?? ""
        self.defaultCourseName = defaultCourse?.name ?? "Choose a course"
        self.hasCourses = defaultCourse != nil
        self.returnHref = selectedCourseID.map { "/app?course=\($0.uuidString)" } ?? "/app"
        self.days = weekDates.map { date in
            let dateKey = planningDateKey(date, calendar: calendar)
            let dueTasks = activeTaskContexts
                .filter { $0.dueInput == dateKey }
                .sorted(by: studyTaskOrder)
            let sessionsOnDate = activeTaskSessions
                .filter { $0.scheduledDate == dateKey }
                .compactMap { session in
                    activeTaskByID[session.$task.id].map { (session: session, task: $0) }
                }
            let legacyFocusTasks = activeTaskContexts
                .filter { $0.startInput == dateKey && !sessionTaskIDs.contains($0.id) }
                .sorted(by: studyTaskOrder)
            return StudyDayContext(
                date: date,
                isToday: calendar.isDate(date, inSameDayAs: today),
                dueTasks: dueTasks,
                studySessions: sessionsOnDate,
                legacyFocusTasks: legacyFocusTasks,
                courseColors: courseColors,
                availability: availability,
                calendar: calendar
            )
        }
        self.workloadDays = days.map(StudyWorkloadDayContext.init)
        let totalMinutes = days.reduce(0) { $0 + $1.workloadMinutes }
        let unestimatedCount = days.reduce(0) { $0 + $1.unestimatedAssignmentCount }
        if unestimatedCount > 0 {
            self.balanceName = "Needs estimates"
            self.balanceDescription = "Add time estimates to see your real workload."
        } else if totalMinutes >= 18 * 60 {
            self.balanceName = "Heavy week"
            self.balanceDescription = "Protect time for the busiest days."
        } else if totalMinutes >= 8 * 60 {
            self.balanceName = "Balanced"
            self.balanceDescription = "Good mix across the week."
        } else {
            self.balanceName = "Light week"
            self.balanceDescription = "Room to work ahead."
        }
        self.unscheduledAssignmentCount = activeTaskContexts.filter { !$0.hasDueDate }.count
        self.hasUnscheduledAssignments = unscheduledAssignmentCount > 0
        self.unestimatedAssignmentCount = days.reduce(0) { $0 + $1.unestimatedAssignmentCount }
        self.hasUnestimatedAssignments = unestimatedAssignmentCount > 0
        let todayKey = planningDateKey(today, calendar: calendar)
        let plannedMinutesByTask = Dictionary(grouping: activeTaskSessions, by: \.$task.id)
            .mapValues { sessions in
                sessions.reduce(0) { total, session in
                    total + studySessionCountedMinutes(session, todayKey: todayKey)
                }
            }
        self.planCandidates = activeTaskContexts
            .sorted(by: studyTaskOrder)
            .compactMap { task in
                guard task.hasEstimate else { return nil }
                let legacyMinutes = sessionTaskIDs.contains(task.id) || task.startInput.isEmpty
                    ? 0
                    : task.estimatedMinutes
                let remainingMinutes = max(
                    0,
                    task.estimatedMinutes - (plannedMinutesByTask[task.id] ?? 0) - legacyMinutes
                )
                guard remainingMinutes > 0 else { return nil }
                return StudyPlanCandidateContext(task: task, remainingMinutes: remainingMinutes)
            }
        self.hasPlanCandidates = !planCandidates.isEmpty
        self.unplannedFocusCount = planCandidates.count
        self.hasUnplannedFocus = unplannedFocusCount > 0
        self.studyStreakDays = studyCompletionStreakDays(
            completedDates: Set(
                taskSessions.filter { $0.state == .completed }.map(\.scheduledDate)
            ),
            referenceDate: today,
            calendar: calendar
        )
        self.studySettings = settingsContext
        let dueDateByTaskID = Dictionary(
            uniqueKeysWithValues: activeTaskContexts.compactMap { task in
                task.dueInput.isEmpty ? nil : (task.id, task.dueInput)
            }
        )
        self.recovery = StudyRecoveryContext(
            analysis: StudyRecoveryService.analyze(
                sessions: activeTaskSessions,
                dueDateByTaskID: dueDateByTaskID,
                availability: availability,
                timeZoneIdentifier: timeZoneIdentifier,
                referenceDate: referenceDate
            )
        )
        self.estimationInbox = activeTaskContexts
            .filter { !$0.hasEstimate }
            .sorted(by: studyTaskOrder)
            .map { task in
                StudyEstimateInboxItemContext(
                    task: task,
                    presets: settingsContext.estimatePresets
                )
            }
        self.hasEstimationInbox = !estimationInbox.isEmpty
        self.onboarding = StudyOnboardingContext(
            hasCanvasConnection: hasCanvasConnection,
            timeZoneConfirmed: settingsContext.timeZoneConfirmed,
            availabilityConfigured: settingsContext.availabilityConfigured,
            hasAssignments: !activeTaskContexts.isEmpty,
            hasMissingEstimates: !estimationInbox.isEmpty,
            hasStudyPlan: activeTaskSessions.contains { $0.state != .skipped }
        )
    }
}

struct StudyCourseContext: Encodable {
    let id: UUID
    let name: String
    let href: String
    let colorClass: String
    let isSelected: Bool
    let gradeDisplay: String
    let hasGrade: Bool

    init(course: BoardNavigationContext, tasks: [TaskCardContext], selectedCourseID: UUID?) {
        self.id = course.id
        self.name = course.name
        self.href = "/app?course=\(course.id.uuidString)"
        self.colorClass = course.courseColorClass
        self.isSelected = course.id == selectedCourseID
        if course.isCanvasLinked {
            self.hasGrade = true
            self.gradeDisplay = course.canvasGradeDisplay
        } else {
            let grades = tasks.filter { $0.boardID == course.id && $0.hasGrade }
            let earned = grades.reduce(0) { $0 + $1.gradeEarned }
            let possible = grades.reduce(0) { $0 + $1.gradePossible }
            self.hasGrade = possible > 0
            self.gradeDisplay = hasGrade ? "\(Int((earned / possible * 100).rounded()))%" : "No grades"
        }
    }
}

struct StudyDayContext: Encodable {
    let weekdayLabel: String
    let dateLabel: String
    let dateInput: String
    let isToday: Bool
    let assignments: [StudyAssignmentContext]
    let assignmentCount: Int
    let hasAssignments: Bool
    let focusBlocks: [StudyAssignmentContext]
    let focusBlockCount: Int
    let hasFocusBlocks: Bool
    let workloadMinutes: Int
    let unestimatedAssignmentCount: Int
    let workloadLabel: String
    let workloadClass: String
    let availableMinutes: Int
    let availableLabel: String
    let isBlocked: Bool
    let isOverloaded: Bool

    init(
        date: Date,
        isToday: Bool,
        dueTasks: [TaskCardContext],
        studySessions: [(session: StudySession, task: TaskCardContext)],
        legacyFocusTasks: [TaskCardContext],
        courseColors: [UUID: String],
        availability: StudyAvailability,
        calendar: Calendar
    ) {
        self.weekdayLabel = planningDateLabel(date, format: "EEE", calendar: calendar)
        self.dateLabel = planningDateLabel(date, format: "MMM d", calendar: calendar)
        self.dateInput = planningDateKey(date, calendar: calendar)
        self.isToday = isToday
        self.assignments = dueTasks.map {
            StudyAssignmentContext(
                task: $0,
                courseColorClass: courseColors[$0.boardID] ?? "course-blue"
            )
        }
        self.assignmentCount = assignments.count
        self.hasAssignments = !assignments.isEmpty
        let sessionBlocks = studySessions.map { value in
            StudyAssignmentContext(
                task: value.task,
                courseColorClass: courseColors[value.task.boardID] ?? "course-blue",
                plannedMinutes: value.session.plannedMinutes,
                studySessionID: value.session.id,
                scheduledDate: value.session.scheduledDate,
                sessionState: value.session.state,
                actualMinutes: value.session.actualMinutes,
                completedAt: value.session.completedAt
            )
        }
        let legacyBlocks = legacyFocusTasks.map {
            StudyAssignmentContext(
                task: $0,
                courseColorClass: courseColors[$0.boardID] ?? "course-blue"
            )
        }
        self.focusBlocks = sessionBlocks + legacyBlocks
        self.focusBlockCount = focusBlocks.count
        self.hasFocusBlocks = !focusBlocks.isEmpty
        self.workloadMinutes = focusBlocks.reduce(0) { $0 + $1.estimatedMinutes }
        self.availableMinutes = availability.availableMinutes(
            on: date,
            dateKey: dateInput,
            calendar: calendar
        )
        self.availableLabel = displayDuration(availableMinutes)
        self.isBlocked = availability.blockedDates.contains(dateInput)
        self.isOverloaded = workloadMinutes > availableMinutes
        self.unestimatedAssignmentCount = dueTasks.filter { !$0.hasEstimate }.count
        switch workloadMinutes {
        case 0:
            self.workloadLabel = "Unplanned"
            self.workloadClass = "empty"
        case 1..<120:
            self.workloadLabel = "Light"
            self.workloadClass = "light"
        case 120..<240:
            self.workloadLabel = "Moderate"
            self.workloadClass = "medium"
        default:
            self.workloadLabel = "Heavy"
            self.workloadClass = "heavy"
        }
    }
}

/// A compact queue item supplies the plan dialog with only the data needed to
/// choose an assignment and place its work on a day.
struct StudyPlanCandidateContext: Encodable {
    let id: UUID
    let title: String
    let courseName: String
    let dueDisplay: String
    let effortLabel: String
    let remainingMinutes: Int
    let remainingDisplay: String

    init(task: TaskCardContext, remainingMinutes: Int) {
        self.id = task.id
        self.title = task.title
        self.courseName = task.boardName
        self.dueDisplay = task.dueDisplay
        self.effortLabel = task.estimatedDisplay
        self.remainingMinutes = remainingMinutes
        self.remainingDisplay = displayDuration(remainingMinutes)
    }
}

struct StudyRecoveryContext: Encodable {
    let missedSessionCount: Int
    let deadlineChangeCount: Int
    let overloadedDayCount: Int
    let issueCount: Int
    let hasIssues: Bool
    let summary: String

    init(analysis: StudyRecoveryAnalysis) {
        self.missedSessionCount = analysis.missedSessionIDs.count
        self.deadlineChangeCount = analysis.deadlineChangedSessionIDs.count
        self.overloadedDayCount = analysis.overloadedDates.count
        self.issueCount = analysis.issueCount
        self.hasIssues = issueCount > 0
        let parts = [
            missedSessionCount > 0 ? "\(missedSessionCount) missed" : nil,
            deadlineChangeCount > 0 ? "\(deadlineChangeCount) after a changed deadline" : nil,
            overloadedDayCount > 0 ? "\(overloadedDayCount) overloaded" : nil,
        ].compactMap { $0 }
        self.summary = parts.isEmpty
            ? "Your current week still fits."
            : parts.joined(separator: ", ") + "."
    }
}

struct StudyEstimateInboxItemContext: Encodable {
    let id: UUID
    let title: String
    let courseName: String
    let dueDisplay: String
    let typeName: String
    let suggestedMinutes: Int
    let suggestedPresetID: String

    init(task: TaskCardContext, presets: [StudyEstimatePreset]) {
        let assignmentType = studyAssignmentType(title: task.title, labels: task.labels)
        let searchText = ([task.title] + task.labels).joined(separator: " ").lowercased()
        let preset = presets.first { preset in
            preset.keywords.contains { searchText.contains($0.lowercased()) }
        }
        self.id = task.id
        self.title = task.title
        self.courseName = task.boardName
        self.dueDisplay = task.dueDisplay
        self.typeName = assignmentType.name
        self.suggestedMinutes = preset?.minutes ?? 60
        self.suggestedPresetID = preset?.id ?? ""
    }
}

struct StudyOnboardingStepContext: Encodable {
    let key: String
    let title: String
    let description: String
    let href: String
    let isComplete: Bool
    let isCurrent: Bool
}

struct StudyOnboardingContext: Encodable {
    let steps: [StudyOnboardingStepContext]
    let completedStepCount: Int
    let isVisible: Bool
    let nextStepKey: String

    init(
        hasCanvasConnection: Bool,
        timeZoneConfirmed: Bool,
        availabilityConfigured: Bool,
        hasAssignments: Bool,
        hasMissingEstimates: Bool,
        hasStudyPlan: Bool
    ) {
        let values = [
            ("canvas", "Connect Canvas", "Bring in courses and deadlines.", "/app/settings/integrations", hasCanvasConnection),
            ("timezone", "Confirm your time zone", "Keep deadlines and study days local.", "", timeZoneConfirmed),
            ("availability", "Set your real week", "Add study capacity, classes, work, and blocked dates.", "", availabilityConfigured),
            ("estimates", "Estimate assignments", "Give every deadline enough study time.", "", hasAssignments && !hasMissingEstimates),
            ("plan", "Build your first week", "Place estimated work into available time.", "", hasStudyPlan),
        ]
        let currentKey = values.first { !$0.4 }?.0 ?? ""
        self.steps = values.map { value in
            StudyOnboardingStepContext(
                key: value.0,
                title: value.1,
                description: value.2,
                href: value.3,
                isComplete: value.4,
                isCurrent: value.0 == currentKey
            )
        }
        self.completedStepCount = values.filter { $0.4 }.count
        self.isVisible = completedStepCount < values.count
        self.nextStepKey = currentKey
    }
}

struct StudyAssignmentContext: Encodable {
    let href: String
    let title: String
    let courseName: String
    let courseColorClass: String
    let dueTime: String
    let typeName: String
    let typeIcon: String
    let estimatedMinutes: Int
    let effortLabel: String
    let hasEstimate: Bool
    let statusName: String
    let statusValue: String
    let statusColorClass: String
    let statusCustomColor: String
    let priorityName: String
    let priorityValue: String
    let priorityColorClass: String
    let priorityCustomColor: String
    let assigneeName: String
    let dueDisplay: String
    let description: String
    let studySessionID: String
    let taskID: String
    let scheduledDate: String
    let hasStudySession: Bool
    let sessionState: String
    let actualMinutes: Int?
    let completedAt: Date?
    let isPlannedSession: Bool

    init(
        task: TaskCardContext,
        courseColorClass: String,
        plannedMinutes: Int? = nil,
        studySessionID: UUID? = nil,
        scheduledDate: String = "",
        sessionState: StudySessionState = .planned,
        actualMinutes: Int? = nil,
        completedAt: Date? = nil
    ) {
        let assignmentType = studyAssignmentType(title: task.title, labels: task.labels)
        self.href = task.href
        self.title = task.title
        self.courseName = task.boardName
        self.courseColorClass = courseColorClass
        self.dueTime = task.dueTimeDisplay
        self.typeName = assignmentType.name
        self.typeIcon = assignmentType.icon
        let sessionMinutes = if studySessionID == nil {
            plannedMinutes
        } else if sessionState == .skipped {
            0
        } else if sessionState == .completed {
            actualMinutes ?? plannedMinutes
        } else {
            plannedMinutes
        }
        self.estimatedMinutes = sessionMinutes ?? task.estimatedMinutes
        self.effortLabel = sessionMinutes.map(displayDuration) ?? task.estimatedDisplay
        self.hasEstimate = plannedMinutes != nil || task.hasEstimate
        self.statusName = task.statusName
        self.statusValue = task.statusValue
        self.statusColorClass = task.statusColorClass
        self.statusCustomColor = task.statusCustomColor
        self.priorityName = task.priorityName
        self.priorityValue = task.priorityValue
        self.priorityColorClass = task.priorityColorClass
        self.priorityCustomColor = task.priorityCustomColor
        self.assigneeName = task.assigneeName
        self.dueDisplay = task.dueDisplay
        self.description = task.description
        self.studySessionID = studySessionID?.uuidString ?? ""
        self.taskID = task.id.uuidString
        self.scheduledDate = scheduledDate
        self.hasStudySession = studySessionID != nil
        self.sessionState = studySessionID == nil ? "" : sessionState.rawValue
        self.actualMinutes = actualMinutes
        self.completedAt = completedAt
        self.isPlannedSession = studySessionID != nil && sessionState == .planned
    }
}

struct StudyWorkloadDayContext: Encodable {
    let dayLabel: String
    let barClass: String
    let accessibilityLabel: String

    init(day: StudyDayContext) {
        self.dayLabel = String(day.weekdayLabel.prefix(1))
        self.barClass = switch day.workloadMinutes {
        case 0: "empty"
        case 1..<120: "light"
        case 120..<240: "medium"
        default: "heavy"
        }
        self.accessibilityLabel = "\(day.weekdayLabel): \(day.workloadLabel), \(displayDuration(day.workloadMinutes)) planned"
    }
}

private func studyWeekLabel(start: Date, calendar: Calendar) -> String {
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    let startMonth = calendar.component(.month, from: start)
    let endMonth = calendar.component(.month, from: end)
    if startMonth == endMonth {
        return planningDateLabel(start, format: "MMMM d", calendar: calendar)
            + "–"
            + planningDateLabel(end, format: "d", calendar: calendar)
    }
    return planningDateLabel(start, format: "MMM d", calendar: calendar)
        + "–"
        + planningDateLabel(end, format: "MMM d", calendar: calendar)
}

private func studyTaskOrder(_ left: TaskCardContext, _ right: TaskCardContext) -> Bool {
    let order = ["urgent": 0, "high": 1, "medium": 2, "low": 3]
    let leftOrder = order[left.priorityValue] ?? 2
    let rightOrder = order[right.priorityValue] ?? 2
    return leftOrder == rightOrder
        ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        : leftOrder < rightOrder
}

private func studyTaskIsCompleted(_ task: TaskCardContext) -> Bool {
    task.completionStatuses.split(separator: ",").contains(Substring(task.statusValue))
}

/// Counts consecutive completed study days ending today, or yesterday when the
/// student has not completed today's work yet. Plans and skips never add credit.
private func studyCompletionStreakDays(
    completedDates: Set<String>,
    referenceDate: Date,
    calendar: Calendar
) -> Int {
    let today = calendar.startOfDay(for: referenceDate)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    var cursor = completedDates.contains(planningDateKey(today, calendar: calendar)) ? today : yesterday
    var streak = 0

    while completedDates.contains(planningDateKey(cursor, calendar: calendar)) {
        streak += 1
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
            break
        }
        cursor = previousDay
    }

    return streak
}

/// Completed minutes and current plans reduce the remaining estimate. Past plans
/// and skipped blocks contribute zero, so missed work returns to the plan queue.
private func studySessionCountedMinutes(_ session: StudySession, todayKey: String) -> Int {
    switch session.state {
    case .completed:
        session.actualMinutes ?? session.plannedMinutes
    case .planned where session.scheduledDate >= todayKey:
        session.plannedMinutes
    default:
        0
    }
}

private func studyAssignmentType(title: String, labels: [String]) -> (name: String, icon: String) {
    let value = title.lowercased()
    if value.contains("lab") {
        return ("Lab Report", "file-text")
    }
    if value.contains("read") || value.contains("chapter") {
        return ("Reading", "book-open")
    }
    if value.contains("discussion") {
        return ("Discussion", "message-square")
    }
    if value.contains("flash") {
        return ("Flashcards", "copy")
    }
    if value.contains("problem") || value.contains("worksheet") {
        return ("Problem Set", "file-text")
    }
    return (labels.first ?? "Assignment", "check-square")
}

struct BoardPageContext: Encodable {
    let id: UUID
    let name: String
    let description: String
    let role: String
    let canEdit: Bool
    let canAdmin: Bool
    let isOwner: Bool
    let views: [BoardViewTabContext]
    let activeView: BoardViewTabContext
    let tasks: [TaskCardContext]
    let hasTasks: Bool
    let groupByName: String
    let hasFilters: Bool
    let filterSummary: String
    let hasSorts: Bool
    let sortSummary: String
    let canDrag: Bool
    let columns: [TaskColumnContext]
    let calendarDays: [CalendarDayContext]
    let calendarMonthLabel: String
    let previousMonthHref: String
    let nextMonthHref: String
    let todayMonthHref: String
    let hasDefaultTemplate: Bool
    let defaultTemplateName: String
    let newTaskTitle: String
    let newTaskDescription: String
    let newTaskStatus: String
    let newTaskStatusName: String
    let newTaskPriority: String
    let newTaskPriorityName: String
    let newTaskLabels: String
    let statusOptions: [TaskOptionContext]
    let severityOptions: [TaskOptionContext]
    let assignmentCount: Int
    let completedAssignmentCount: Int
    let undatedAssignmentCount: Int
    let unestimatedAssignmentCount: Int
    let isCanvasLinked: Bool
    let canvasURL: String
    let canvasCourseCode: String
    let canvasTermName: String
    let canvasGradeDisplay: String
    let canvasHasScore: Bool
    let canvasScorePercent: Double
    let canvasLastSyncDisplay: String
    let studySessions: [StudySessionPageContext]

    init(
        board: Board,
        access: BoardAccess,
        views: [BoardView],
        activeView: BoardView,
        tasks: [TaskCardContext],
        calendarDays: [CalendarDayContext],
        calendarMonthLabel: String,
        previousMonthHref: String,
        nextMonthHref: String,
        todayMonthHref: String,
        defaultTemplate: TaskTemplate?,
        studySessions: [StudySession],
        studyTasks: [TaskCardContext],
        timeZoneIdentifier: String,
        canvasLink: CanvasCourseLink? = nil,
        canvasConnection: CanvasConnection? = nil
    ) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.description = board.description ?? ""
        self.role = access.isOwner ? "Owner" : access.role.rawValue.capitalized
        self.canEdit = access.isOwner || access.role.canEdit
        self.canAdmin = access.isOwner || access.role == .admin
        self.isOwner = access.isOwner
        self.views = try views.map {
            try BoardViewTabContext(view: $0, boardID: board.requireID(), activeID: activeView.requireID())
        }
        self.activeView = try BoardViewTabContext(
            view: activeView,
            boardID: board.requireID(),
            activeID: activeView.requireID()
        )
        self.tasks = tasks
        self.hasTasks = !tasks.isEmpty
        let configuration = activeView.configuration
        let groupBy = configuration?.groupBy ?? "status"
        self.groupByName = groupBy == "priority" ? "Priority" : "Status"
        self.hasFilters = !(configuration?.filters.isEmpty ?? true)
        self.filterSummary = configuration?.filters.first.map {
            "\($0.field.replacingOccurrences(of: "_", with: " ").capitalized): \($0.value)"
        } ?? ""
        self.hasSorts = !(configuration?.sorts.isEmpty ?? true)
        self.sortSummary = configuration?.sorts.first.map {
            "\($0.field.replacingOccurrences(of: "_", with: " ").capitalized) \($0.direction)"
        } ?? ""
        self.canDrag = canEdit && activeView.type == .board && groupBy == "status"
        self.columns = if groupBy == "priority" {
            board.taskSeverities.map { severity in
                TaskColumnContext(
                    value: severity.id,
                    name: severity.name,
                    dotClass: severity.color.cssClass,
                    dotStyle: severity.color.cssStyle,
                    isCompleted: false,
                    tasks: tasks.filter { $0.priorityValue == severity.id }
                )
            }
        } else {
            board.taskStatuses.map { status in
                TaskColumnContext(
                    value: status.id,
                    name: status.name,
                    dotClass: status.color.cssClass,
                    dotStyle: status.color.cssStyle,
                    isCompleted: status.isCompleted,
                    tasks: tasks.filter { $0.statusValue == status.id }
                )
            }
        }
        self.calendarDays = calendarDays
        self.calendarMonthLabel = calendarMonthLabel
        self.previousMonthHref = previousMonthHref
        self.nextMonthHref = nextMonthHref
        self.todayMonthHref = todayMonthHref
        self.hasDefaultTemplate = defaultTemplate != nil
        self.defaultTemplateName = defaultTemplate?.name ?? ""
        self.newTaskTitle = defaultTemplate?.title ?? ""
        self.newTaskDescription = defaultTemplate?.description ?? ""
        let defaultStatus = defaultTemplate?.status ?? .backlog
        self.newTaskStatus = defaultStatus.rawValue
        self.newTaskStatusName = board.statusOption(for: defaultStatus).name
        let defaultPriority = defaultTemplate?.priority ?? .medium
        self.newTaskPriority = defaultPriority.rawValue
        self.newTaskPriorityName = board.severityOption(for: defaultPriority).name
        self.newTaskLabels = defaultTemplate?.labels.joined(separator: ", ") ?? ""
        self.statusOptions = board.taskStatuses.map {
            TaskOptionContext(option: $0, selectedValue: defaultStatus.rawValue)
        }
        self.severityOptions = board.taskSeverities.map {
            TaskOptionContext(option: $0, selectedValue: defaultPriority.rawValue)
        }
        self.assignmentCount = tasks.count
        self.completedAssignmentCount = tasks.filter {
            board.isCompleted(TaskStatus(rawValue: $0.statusValue))
        }.count
        self.undatedAssignmentCount = tasks.filter { !$0.hasDueDate }.count
        self.unestimatedAssignmentCount = tasks.filter { !$0.hasEstimate }.count
        self.isCanvasLinked = canvasLink != nil
        self.canvasURL = canvasLink?.canvasCourseURL ?? ""
        self.canvasCourseCode = canvasLink?.courseCode ?? ""
        self.canvasTermName = canvasLink?.termName ?? ""
        self.canvasGradeDisplay = canvasCourseGradeDisplay(link: canvasLink)
        self.canvasHasScore = canvasLink?.currentScore != nil
        self.canvasScorePercent = min(100, max(0, canvasLink?.currentScore ?? 0))
        self.canvasLastSyncDisplay = canvasConnection?.lastSuccessfulSyncAt.map(displayDate) ?? "Not synced yet"
        let taskByID = Dictionary(uniqueKeysWithValues: studyTasks.map { ($0.id, $0) })
        let calendar = planningCalendar(timeZoneIdentifier: timeZoneIdentifier)
        self.studySessions = try studySessions
            .filter { $0.state == .planned }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .compactMap { session in
                guard let task = taskByID[session.$task.id] else { return nil }
                return try StudySessionPageContext(session: session, task: task, calendar: calendar)
            }
    }
}

/// Canvas publishes the authoritative course total. A missing score and grade
/// means Canvas has hidden the total, so a local points sum would be misleading.
private func canvasCourseGradeDisplay(link: CanvasCourseLink?) -> String {
    guard let link else { return "" }
    let score = link.currentScore.map { "\(displayScore($0))%" }
    let parts = [score, link.currentGrade]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    return parts.isEmpty ? "Hidden in Canvas" : parts.joined(separator: " · ")
}

struct BoardViewTabContext: Encodable {
    let id: UUID
    let name: String
    let type: String
    let href: String
    let isActive: Bool
    let isBoard: Bool
    let isTable: Bool
    let isCalendar: Bool
    let isGantt: Bool
    let isGallery: Bool
    let icon: String

    init(view: BoardView, boardID: UUID, activeID: UUID) throws {
        let id = try view.requireID()
        self.id = id
        self.name = view.name
        self.type = view.type.rawValue
        self.href = "/app/boards/\(boardID)/views/\(id)"
        self.isActive = id == activeID
        self.isBoard = view.type == .board
        self.isTable = view.type == .table
        self.isCalendar = view.type == .calendar
        self.isGantt = view.type == .gantt
        self.isGallery = view.type == .gallery
        self.icon = switch view.type {
        case .board: "columns-3"
        case .table: "table-2"
        case .calendar: "calendar-days"
        case .gantt: "chart-bar-horizontal"
        case .gallery: "gallery-horizontal-end"
        }
    }
}
