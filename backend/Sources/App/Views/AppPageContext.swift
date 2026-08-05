import Foundation

enum AppPageKind {
    case overview
    case semester
    case board
    case tasks
    case archivedTasks
    case taskDetail
    case settings
    case apiKeys
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
    let isAPIKeys: Bool
    let isBoardSettings: Bool
    let overview: OverviewPageContext?
    let semester: SemesterPageContext?
    let board: BoardPageContext?
    let tasks: TasksPageContext?
    let taskDetail: TaskDetailPageContext?
    let settings: SettingsPageContext?
    let apiKeys: APIKeysPageContext?
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
        apiKeys: APIKeysPageContext?,
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
        self.isSettings = pageKind == .settings || pageKind == .apiKeys
        self.isProfileSettings = pageKind == .settings
        self.isAPIKeys = pageKind == .apiKeys
        self.isBoardSettings = pageKind == .boardSettings
        self.overview = overview
        self.semester = semester
        self.board = board
        self.tasks = tasks
        self.taskDetail = taskDetail
        self.settings = settings
        self.apiKeys = apiKeys
        self.boardSettings = boardSettings
    }
}

struct CommonPageContext: Encodable {
    let userName: String
    let userEmail: String
    let userAvatar: AvatarContext
    let boards: [BoardNavigationContext]
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

    init(board: Board, firstViewID: UUID?, courseColorClass: String) throws {
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

    init(
        tasks: [TaskCardContext],
        courses: [BoardNavigationContext],
        selectedCourseID: UUID?,
        referenceDate: Date = Date()
    ) {
        let calendar = studyCalendar()
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
            let dateKey = inputDate(date)
            let dueTasks = activeTaskContexts
                .filter { $0.dueInput == dateKey }
                .sorted(by: studyTaskOrder)
            let focusTasks = activeTaskContexts
                .filter { $0.startInput == dateKey && $0.dueInput != dateKey }
                .sorted(by: studyTaskOrder)
            // A task planned for its due date does not need a duplicate focus
            // card, but its estimate must still count toward that day's load.
            let workloadTasks = activeTaskContexts
                .filter {
                    $0.startInput == dateKey
                        || ($0.dueInput == dateKey && $0.startInput.isEmpty)
                }
                .sorted(by: studyTaskOrder)
            return StudyDayContext(
                date: date,
                isToday: calendar.isDate(date, inSameDayAs: today),
                dueTasks: dueTasks,
                focusTasks: focusTasks,
                workloadTasks: workloadTasks,
                courseColors: courseColors
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
        self.planCandidates = activeTaskContexts
            .filter { $0.startInput.isEmpty }
            .sorted(by: studyTaskOrder)
            .map(StudyPlanCandidateContext.init)
        self.hasPlanCandidates = !planCandidates.isEmpty
        self.unplannedFocusCount = planCandidates.count
        self.hasUnplannedFocus = unplannedFocusCount > 0
        self.studyStreakDays = studyPlanningStreakDays(
            tasks: taskContexts.filter { !$0.isArchived },
            referenceDate: today,
            calendar: calendar
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
        let grades = tasks.filter { $0.boardID == course.id && $0.hasGrade }
        let earned = grades.reduce(0) { $0 + $1.gradeEarned }
        let possible = grades.reduce(0) { $0 + $1.gradePossible }
        self.hasGrade = possible > 0
        self.gradeDisplay = hasGrade ? "\(Int((earned / possible * 100).rounded()))%" : "No grades"
    }
}

struct StudyDayContext: Encodable {
    let weekdayLabel: String
    let dateLabel: String
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

    init(
        date: Date,
        isToday: Bool,
        dueTasks: [TaskCardContext],
        focusTasks: [TaskCardContext],
        workloadTasks: [TaskCardContext],
        courseColors: [UUID: String]
    ) {
        self.weekdayLabel = studyDateLabel(date, format: "EEE")
        self.dateLabel = studyDateLabel(date, format: "MMM d")
        self.isToday = isToday
        self.assignments = dueTasks.map {
            StudyAssignmentContext(
                task: $0,
                courseColorClass: courseColors[$0.boardID] ?? "course-blue"
            )
        }
        self.assignmentCount = assignments.count
        self.hasAssignments = !assignments.isEmpty
        self.focusBlocks = focusTasks.map {
            StudyAssignmentContext(
                task: $0,
                courseColorClass: courseColors[$0.boardID] ?? "course-blue"
            )
        }
        self.focusBlockCount = focusBlocks.count
        self.hasFocusBlocks = !focusBlocks.isEmpty
        let workloadAssignments = workloadTasks.map {
            StudyAssignmentContext(
                task: $0,
                courseColorClass: courseColors[$0.boardID] ?? "course-blue"
            )
        }
        self.workloadMinutes = workloadAssignments.reduce(0) { $0 + $1.estimatedMinutes }
        self.unestimatedAssignmentCount = workloadAssignments.filter { !$0.hasEstimate }.count
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

    init(task: TaskCardContext) {
        self.id = task.id
        self.title = task.title
        self.courseName = task.boardName
        self.dueDisplay = task.dueDisplay
        self.effortLabel = task.estimatedDisplay
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

    init(task: TaskCardContext, courseColorClass: String) {
        let assignmentType = studyAssignmentType(title: task.title, labels: task.labels)
        self.href = task.href
        self.title = task.title
        self.courseName = task.boardName
        self.courseColorClass = courseColorClass
        self.dueTime = task.dueTimeDisplay
        self.typeName = assignmentType.name
        self.typeIcon = assignmentType.icon
        self.estimatedMinutes = task.estimatedMinutes
        self.effortLabel = task.estimatedDisplay
        self.hasEstimate = task.hasEstimate
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

private func studyCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}

private func studyWeekLabel(start: Date, calendar: Calendar) -> String {
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    let startMonth = calendar.component(.month, from: start)
    let endMonth = calendar.component(.month, from: end)
    if startMonth == endMonth {
        return "\(studyDateLabel(start, format: "MMMM d"))–\(studyDateLabel(end, format: "d"))"
    }
    return "\(studyDateLabel(start, format: "MMM d"))–\(studyDateLabel(end, format: "MMM d"))"
}

private func studyDateLabel(_ date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter.string(from: date)
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

/// Counts consecutive planned study days ending today, or yesterday when the
/// user has not planned today's work yet. Empty and future dates do not extend
/// the streak, and completed tasks remain valid evidence of past study plans.
private func studyPlanningStreakDays(
    tasks: [TaskCardContext],
    referenceDate: Date,
    calendar: Calendar
) -> Int {
    let plannedDates = Set(tasks.map(\.startInput).filter { !$0.isEmpty })
    let today = calendar.startOfDay(for: referenceDate)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    var cursor = plannedDates.contains(inputDate(today)) ? today : yesterday
    var streak = 0

    while plannedDates.contains(inputDate(cursor)) {
        streak += 1
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
            break
        }
        cursor = previousDay
    }

    return streak
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
        defaultTemplate: TaskTemplate?
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
        self.groupByName = groupBy == "priority" ? "Severity" : "Status"
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
    }
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
        self.isGallery = view.type == .gallery
        self.icon = switch view.type {
        case .board: "columns-3"
        case .table: "table-2"
        case .calendar: "calendar-days"
        case .gallery: "gallery-horizontal-end"
        }
    }
}
