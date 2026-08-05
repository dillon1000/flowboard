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

enum StudyPlanningService {
    /// Splits remaining task estimates across the current week without exceeding
    /// the user's daily limit. Existing sessions consume both the task
    /// estimate and daily capacity, which makes repeated requests idempotent.
    static func plan(
        tasks: [StudyPlanningTask],
        sessions: [StudyPlanningSession],
        dailyLimitMinutes: Int,
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
                .filter { $0.scheduledDate == key }
                .reduce(0) { $0 + $1.plannedMinutes }
            availableMinutesByDate[key] = max(0, dailyLimitMinutes - existingMinutes)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let plannedMinutesByTask = Dictionary(grouping: sessions, by: \.taskID)
            .mapValues { taskSessions in
                taskSessions.reduce(0) { $0 + $1.plannedMinutes }
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
