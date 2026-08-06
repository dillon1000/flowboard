import Foundation

struct StudyPlanningTask: Sendable {
    let id: UUID
    let dueDate: String
    let estimatedMinutes: Int
    let priority: String
}

struct StudyPlanningSession: Sendable {
    let taskID: UUID
    let scheduledDate: String
    let plannedMinutes: Int
    let state: StudySessionState
    let actualMinutes: Int?
}

struct StudySessionAllocation: Sendable {
    let taskID: UUID
    let scheduledDate: String
    let plannedMinutes: Int
}

struct StudyPlanningResult: Sendable {
    let allocations: [StudySessionAllocation]
    let remainingMinutes: Int
    let unplannedTaskCount: Int
}

struct StudyAvailability: Sendable {
    let weekdayCapacityMinutes: [String: Int]
    let blockedDates: Set<String>
    let recurringCommitments: [StudyRecurringCommitment]
    let calendarConflicts: [StudyCalendarConflict]

    init(settings: StudySettings?) {
        self.weekdayCapacityMinutes = settings?.weekdayCapacityMinutes
            ?? StudySettings.defaultWeekdayCapacityMinutes
        self.blockedDates = Set(settings?.blockedDates ?? [])
        self.recurringCommitments = settings?.recurringCommitments ?? []
        self.calendarConflicts = settings?.calendarConflicts ?? []
    }

    init(dailyLimitMinutes: Int) {
        self.weekdayCapacityMinutes = Dictionary(
            uniqueKeysWithValues: StudySettings.defaultWeekdayCapacityMinutes.keys.map {
                ($0, dailyLimitMinutes)
            }
        )
        self.blockedDates = []
        self.recurringCommitments = []
        self.calendarConflicts = []
    }

    /// Returns usable study minutes after fixed commitments. A blocked date has
    /// zero capacity even when the weekday normally has room.
    func availableMinutes(on date: Date, dateKey: String, calendar: Calendar) -> Int {
        guard !blockedDates.contains(dateKey) else { return 0 }
        let weekdayIndex = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        let weekdayKeys = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        ]
        let grossCapacity = weekdayCapacityMinutes[weekdayKeys[weekdayIndex - 1]] ?? 0
        let recurringMinutes = recurringCommitments
            .filter { $0.weekdays.contains(weekdayIndex) }
            .reduce(0) { $0 + durationMinutes(start: $1.startTime, end: $1.endTime) }
        let conflictMinutes = calendarConflicts
            .filter { $0.date == dateKey }
            .reduce(0) { $0 + durationMinutes(start: $1.startTime, end: $1.endTime) }
        return max(0, grossCapacity - recurringMinutes - conflictMinutes)
    }

    private func durationMinutes(start: String, end: String) -> Int {
        func value(_ time: String) -> Int {
            let parts = time.split(separator: ":")
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
                return 0
            }
            return hour * 60 + minute
        }
        return max(0, value(end) - value(start))
    }
}

struct StudyRecoveryAnalysis: Sendable {
    let missedSessionIDs: Set<UUID>
    let deadlineChangedSessionIDs: Set<UUID>
    let overloadedSessionIDs: Set<UUID>
    let overloadedDates: [String]

    var affectedSessionIDs: Set<UUID> {
        missedSessionIDs.union(deadlineChangedSessionIDs).union(overloadedSessionIDs)
    }

    var issueCount: Int {
        missedSessionIDs.count + deadlineChangedSessionIDs.count + overloadedDates.count
    }
}

enum StudyRecoveryService {
    /// Finds plans that can no longer be followed. Overloaded days keep the
    /// earliest blocks and return later blocks to the queue until the day fits.
    static func analyze(
        sessions: [StudySession],
        dueDateByTaskID: [UUID: String],
        availability: StudyAvailability,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) -> StudyRecoveryAnalysis {
        let calendar = planningCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let todayKey = planningDateKey(referenceDate, calendar: calendar)
        let plannedSessions = sessions.filter { $0.state == .planned }
        let missed = Set(plannedSessions.compactMap { session -> UUID? in
            guard session.scheduledDate < todayKey else { return nil }
            return session.id
        })
        let deadlineChanged = Set(plannedSessions.compactMap { session -> UUID? in
            guard let dueDate = dueDateByTaskID[session.$task.id] else { return nil }
            return session.scheduledDate > max(todayKey, dueDate) ? session.id : nil
        })

        var overloadedSessionIDs: Set<UUID> = []
        var overloadedDates: [String] = []
        let candidates = plannedSessions.filter { session in
            guard session.scheduledDate >= todayKey else { return false }
            guard let sessionID = session.id else { return true }
            return !missed.contains(sessionID) && !deadlineChanged.contains(sessionID)
        }
        for (dateKey, dateSessions) in Dictionary(grouping: candidates, by: \.scheduledDate) {
            guard let date = planningDate(dateKey, calendar: calendar) else { continue }
            let capacity = availability.availableMinutes(on: date, dateKey: dateKey, calendar: calendar)
            var total = dateSessions.reduce(0) { $0 + $1.plannedMinutes }
            guard total > capacity else { continue }
            overloadedDates.append(dateKey)
            for session in dateSessions.sorted(by: { $0.plannedMinutes > $1.plannedMinutes }) {
                guard total > capacity, let sessionID = session.id else { break }
                overloadedSessionIDs.insert(sessionID)
                total -= session.plannedMinutes
            }
        }
        return StudyRecoveryAnalysis(
            missedSessionIDs: missed,
            deadlineChangedSessionIDs: deadlineChanged,
            overloadedSessionIDs: overloadedSessionIDs,
            overloadedDates: overloadedDates.sorted()
        )
    }
}

enum StudyPlanningService {
    /// Splits remaining task estimates across the current week without exceeding
    /// the user's daily limit. Completed work and active plans consume the task
    /// estimate. A past plan does not, because that work still needs a new time.
    static func plan(
        tasks: [StudyPlanningTask],
        sessions: [StudyPlanningSession],
        dailyLimitMinutes: Int,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) -> StudyPlanningResult {
        plan(
            tasks: tasks,
            sessions: sessions,
            availability: StudyAvailability(dailyLimitMinutes: dailyLimitMinutes),
            timeZoneIdentifier: timeZoneIdentifier,
            referenceDate: referenceDate
        )
    }

    static func plan(
        tasks: [StudyPlanningTask],
        sessions: [StudyPlanningSession],
        availability: StudyAvailability,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) -> StudyPlanningResult {
        let calendar = planningCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: referenceDate)
        let todayKey = planningDateKey(today, calendar: calendar)
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? today
        let weekEndKey = planningDateKey(weekEnd, calendar: calendar)

        var availableMinutesByDate: [String: Int] = [:]
        var cursor = today
        while cursor <= weekEnd {
            let key = planningDateKey(cursor, calendar: calendar)
            let existingMinutes = sessions
                .filter { session in
                    session.scheduledDate == key
                        && session.state != .skipped
                        && (session.state == .completed || session.scheduledDate >= todayKey)
                }
                .reduce(0) { total, session in
                    total + (session.state == .completed
                        ? session.actualMinutes ?? session.plannedMinutes
                        : session.plannedMinutes)
                }
            let capacity = availability.availableMinutes(on: cursor, dateKey: key, calendar: calendar)
            availableMinutesByDate[key] = max(0, capacity - existingMinutes)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let plannedMinutesByTask = Dictionary(grouping: sessions, by: \.taskID)
            .mapValues { taskSessions in
                taskSessions.reduce(0) { total, session in
                    switch session.state {
                    case .completed:
                        total + (session.actualMinutes ?? session.plannedMinutes)
                    case .planned where session.scheduledDate >= todayKey:
                        total + session.plannedMinutes
                    default:
                        total
                    }
                }
            }
        let priorityOrder = ["urgent": 0, "high": 1, "medium": 2, "low": 3]
        let orderedTasks = tasks.sorted { left, right in
            if left.dueDate != right.dueDate { return left.dueDate < right.dueDate }
            return (priorityOrder[left.priority] ?? 2) < (priorityOrder[right.priority] ?? 2)
        }

        struct AllocationKey: Hashable {
            let taskID: UUID
            let scheduledDate: String
        }
        var allocatedMinutes: [AllocationKey: Int] = [:]
        var remainingMinutes = 0
        var unplannedTaskCount = 0

        for task in orderedTasks {
            var remaining = max(0, task.estimatedMinutes - (plannedMinutesByTask[task.id] ?? 0))
            guard remaining > 0 else { continue }
            let lastDateKey = max(todayKey, min(task.dueDate, weekEndKey))

            while remaining >= 5 {
                let dateKeys = availableMinutesByDate.keys
                    .filter { $0 >= todayKey && $0 <= lastDateKey && (availableMinutesByDate[$0] ?? 0) >= 5 }
                    .sorted()
                guard !dateKeys.isEmpty else { break }
                let share = max(
                    5,
                    Int(ceil(Double(remaining) / Double(dateKeys.count) / 5.0)) * 5
                )
                var allocatedInPass = 0
                for dateKey in dateKeys {
                    let capacity = availableMinutesByDate[dateKey] ?? 0
                    let minutes = min(remaining, min(capacity, share))
                    guard minutes >= 5 else { continue }
                    let key = AllocationKey(taskID: task.id, scheduledDate: dateKey)
                    allocatedMinutes[key, default: 0] += minutes
                    availableMinutesByDate[dateKey] = capacity - minutes
                    remaining -= minutes
                    allocatedInPass += minutes
                    if remaining < 5 { break }
                }
                if allocatedInPass == 0 { break }
            }

            if remaining > 0 {
                remainingMinutes += remaining
                unplannedTaskCount += 1
            }
        }

        let allocations = allocatedMinutes
            .map { key, minutes in
                StudySessionAllocation(
                    taskID: key.taskID,
                    scheduledDate: key.scheduledDate,
                    plannedMinutes: minutes
                )
            }
            .sorted { left, right in
                if left.scheduledDate != right.scheduledDate {
                    return left.scheduledDate < right.scheduledDate
                }
                return left.taskID.uuidString < right.taskID.uuidString
            }
        return StudyPlanningResult(
            allocations: allocations,
            remainingMinutes: remainingMinutes,
            unplannedTaskCount: unplannedTaskCount
        )
    }
}
