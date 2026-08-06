import Crypto
import Fluent
import Foundation
import Vapor

enum NotificationType: String, Codable, Sendable {
    case welcome
    case boardMemberAdded = "board_member_added"
    case taskCommentAdded = "task_comment_added"
    case taskAssigned = "task_assigned"
    case taskReminder = "task_reminder"
    case dailyBrief = "daily_brief"
    case weeklyPlanningPrompt = "weekly_planning_prompt"
}

struct NotificationEvent: Codable, Sendable {
    let eventID: UUID
    let deduplicationKey: String
    let type: NotificationType
    let recipient: String
    let data: [String: String]

    init(
        eventID: UUID = UUID(),
        deduplicationKey: String,
        type: NotificationType,
        recipient: String,
        data: [String: String]
    ) {
        self.eventID = eventID
        self.deduplicationKey = deduplicationKey
        self.type = type
        self.recipient = recipient
        self.data = data
    }

    static func welcome(user: User, appURL: String) throws -> Self {
        let userID = try user.requireID()
        return Self(
            deduplicationKey: "welcome:\(userID.uuidString)",
            type: .welcome,
            recipient: user.email,
            data: [
                "recipientName": user.name,
                "appURL": appURL,
            ]
        )
    }

    static func boardMemberAdded(
        member: BoardMember,
        user: User,
        actor: User,
        board: Board,
        appURL: String
    ) throws -> Self {
        let memberID = try member.requireID()
        let boardID = try board.requireID()
        return Self(
            deduplicationKey: "board-member:\(memberID.uuidString)",
            type: .boardMemberAdded,
            recipient: user.email,
            data: [
                "recipientName": user.name,
                "actorName": actor.name,
                "boardName": board.name,
                "role": member.role.rawValue,
                "appURL": appURL + "/app/boards/\(boardID.uuidString)",
            ]
        )
    }

    static func taskCommentAdded(
        comment: TaskComment,
        task: Task,
        board: Board,
        actor: User,
        recipient: User,
        appURL: String
    ) throws -> Self {
        let commentID = try comment.requireID()
        let taskID = try task.requireID()
        let recipientID = try recipient.requireID()
        return Self(
            deduplicationKey: "task-comment:\(commentID.uuidString):\(recipientID.uuidString)",
            type: .taskCommentAdded,
            recipient: recipient.email,
            data: [
                "recipientName": recipient.name,
                "actorName": actor.name,
                "taskTitle": task.title,
                "boardName": board.name,
                "commentPreview": String(comment.body.prefix(500)),
                "taskURL": appURL + task.browserPath,
                "taskID": taskID.uuidString,
            ]
        )
    }

    /// Uses the task mutation timestamp so a retried request does not enqueue a
    /// second email, while a later reassignment creates a new notification key.
    static func taskAssigned(
        task: Task,
        board: Board,
        assignee: User,
        actor: User,
        appURL: String
    ) throws -> Self {
        let taskID = try task.requireID()
        let assigneeID = try assignee.requireID()
        let assignmentVersion = task.updatedAt ?? task.createdAt
        let version = assignmentVersion.map { String(Int64($0.timeIntervalSince1970 * 1_000_000)) } ?? taskID.uuidString
        return Self(
            deduplicationKey: "task-assignment:\(taskID.uuidString):\(assigneeID.uuidString):\(version)",
            type: .taskAssigned,
            recipient: assignee.email,
            data: [
                "recipientName": assignee.name,
                "actorName": actor.name,
                "taskTitle": task.title,
                "boardName": board.name,
                "taskURL": appURL + task.browserPath,
                "taskID": taskID.uuidString,
                "assigneeID": assigneeID.uuidString,
            ]
        )
    }

    static func taskReminder(
        reminder: TaskReminder,
        task: Task,
        board: Board,
        recipient: User,
        appURL: String
    ) throws -> Self {
        let reminderID = try reminder.requireID()
        let taskID = try task.requireID()
        let timeZone = TimeZone(identifier: reminder.timeZoneIdentifier) ?? .current
        let reminderFormatter = DateFormatter()
        reminderFormatter.locale = Locale(identifier: "en_US_POSIX")
        reminderFormatter.timeZone = timeZone
        reminderFormatter.dateFormat = "EEE, MMM d 'at' h:mm a"

        var data = [
            "recipientName": recipient.name,
            "taskTitle": task.title,
            "boardName": board.name,
            "reminderTime": reminderFormatter.string(from: reminder.remindAt),
            "taskURL": appURL + task.browserPath,
            "taskID": taskID.uuidString,
        ]
        if let dueAt = task.dueAt {
            let dueFormatter = DateFormatter()
            dueFormatter.locale = Locale(identifier: "en_US_POSIX")
            dueFormatter.timeZone = timeZone
            dueFormatter.dateFormat = "EEE, MMM d"
            let time = task.dueTime.map { " at \($0)" } ?? ""
            data["taskDue"] = dueFormatter.string(from: dueAt) + time
        }

        return Self(
            deduplicationKey: "task-reminder:\(reminderID.uuidString)",
            type: .taskReminder,
            recipient: recipient.email,
            data: data
        )
    }

    static func dailyBrief(
        user: User,
        dateKey: String,
        dateLabel: String,
        studySessionCount: Int,
        plannedMinutes: Int,
        deadlineCount: Int,
        appURL: String
    ) throws -> Self {
        let userID = try user.requireID()
        return Self(
            deduplicationKey: "daily-brief:\(userID.uuidString):\(dateKey)",
            type: .dailyBrief,
            recipient: user.email,
            data: [
                "recipientName": user.name,
                "dateLabel": dateLabel,
                "studySessionCount": String(studySessionCount),
                "plannedTime": displayDuration(plannedMinutes),
                "deadlineCount": String(deadlineCount),
                "appURL": appURL,
            ]
        )
    }

    static func weeklyPlanningPrompt(
        user: User,
        weekKey: String,
        weekLabel: String,
        unplannedTaskCount: Int,
        remainingMinutes: Int,
        appURL: String
    ) throws -> Self {
        let userID = try user.requireID()
        return Self(
            deduplicationKey: "weekly-planning:\(userID.uuidString):\(weekKey)",
            type: .weeklyPlanningPrompt,
            recipient: user.email,
            data: [
                "recipientName": user.name,
                "weekLabel": weekLabel,
                "unplannedTaskCount": String(unplannedTaskCount),
                "remainingTime": displayDuration(remainingMinutes),
                "appURL": appURL,
            ]
        )
    }
}

struct NotificationConfiguration: Sendable {
    let workerURL: URI
    let sharedSecret: String
    let publicAppURL: String

    static func fromEnvironment() throws -> Self? {
        let workerURLValue = Environment.get("NOTIFICATION_WORKER_URL")
        let sharedSecret = Environment.get("NOTIFICATION_SHARED_SECRET")
        let publicAppURL = Environment.get("PUBLIC_APP_URL")
        guard workerURLValue != nil || sharedSecret != nil || publicAppURL != nil else {
            return nil
        }
        guard
            let workerURLValue,
            let sharedSecret,
            let publicAppURL,
            let workerURL = URL(string: workerURLValue),
            let appURL = URL(string: publicAppURL),
            ["http", "https"].contains(workerURL.scheme?.lowercased()),
            ["http", "https"].contains(appURL.scheme?.lowercased()),
            workerURL.host != nil,
            appURL.host != nil,
            sharedSecret.count >= 32
        else {
            throw NotificationConfigurationError.invalid
        }
        return Self(
            workerURL: URI(string: workerURLValue),
            sharedSecret: sharedSecret,
            publicAppURL: publicAppURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
    }

    func appURL(path: String) -> String {
        publicAppURL + (path.hasPrefix("/") ? path : "/" + path)
    }
}

enum NotificationConfigurationError: Error {
    case invalid
}

struct NotificationClient: Sendable {
    let configuration: NotificationConfiguration

    func send(
        _ event: NotificationEvent,
        using client: any Client
    ) async throws -> String {
        let request = WorkerNotificationRequest(
            eventID: event.eventID,
            type: event.type.rawValue,
            to: event.recipient,
            data: event.data
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(request)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(timestamp.utf8) + Data(".".utf8) + body,
            using: SymmetricKey(data: Data(configuration.sharedSecret.utf8))
        )
        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: "X-Flowboard-Timestamp", value: timestamp)
        headers.replaceOrAdd(
            name: "X-Flowboard-Signature",
            value: "sha256=\(Data(signature).hexString)"
        )
        let response = try await client.post(configuration.workerURL, headers: headers) { request in
            request.body = .init(data: body)
        }
        guard (200..<300).contains(response.status.code) else {
            throw NotificationClientError(statusCode: response.status.code)
        }
        let result = try response.content.decode(WorkerNotificationResponse.self)
        guard !result.messageID.isEmpty else {
            throw NotificationClientError(statusCode: nil)
        }
        return result.messageID
    }
}

struct NotificationClientError: Error, Sendable {
    let statusCode: UInt?

    var isRetryable: Bool {
        guard let statusCode else { return true }
        return statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500
    }
}

enum NotificationService {
    static func enqueue(_ event: NotificationEvent, for req: Request) async {
        guard req.application.notificationConfiguration != nil else {
            return
        }
        do {
            let alreadyQueued = try await NotificationOutbox.query(on: req.db)
                .filter(\.$deduplicationKey == event.deduplicationKey)
                .first() != nil
            guard !alreadyQueued else { return }
            try await NotificationOutbox(event: event).create(on: req.db)
        } catch {
            req.logger.error("Notification outbox insert failed: \(error)")
        }
    }

    static func dispatchPending(
        configuration: NotificationConfiguration,
        database: any Database,
        client: any Client,
        logger: Logger
    ) async {
        let records: [NotificationOutbox]
        do {
            records = try await NotificationOutbox.query(on: database)
                .filter(\.$statusValue == NotificationOutboxStatus.pending.rawValue)
                .filter(\.$nextAttemptAt <= Date())
                .sort(\.$createdAt, .ascending)
                .range(0..<20)
                .all()
        } catch {
            logger.error("Notification outbox query failed: \(error)")
            return
        }

        let notificationClient = NotificationClient(configuration: configuration)
        for record in records {
            await deliver(
                record,
                with: notificationClient,
                database: database,
                client: client,
                logger: logger
            )
        }
    }

    private static func deliver(
        _ record: NotificationOutbox,
        with notificationClient: NotificationClient,
        database: any Database,
        client: any Client,
        logger: Logger
    ) async {
        guard
            let recordID = record.id,
            let type = NotificationType(rawValue: record.eventType)
        else {
            record.status = .failed
            record.lastError = "The notification record has an invalid event type."
            try? await record.update(on: database)
            return
        }

        record.attempts += 1
        let event = NotificationEvent(
            eventID: recordID,
            deduplicationKey: record.deduplicationKey,
            type: type,
            recipient: record.recipient,
            data: record.payload
        )
        do {
            let messageID = try await notificationClient.send(event, using: client)
            record.status = .sent
            record.providerMessageID = messageID
            record.lastError = nil
            record.sentAt = Date()
        } catch let error as NotificationClientError {
            record.lastError = String(describing: error).prefix(1_000).description
            if error.isRetryable && record.attempts < 10 {
                record.status = .pending
                record.nextAttemptAt = Date(timeIntervalSinceNow: retryDelay(for: record.attempts))
            } else {
                record.status = .failed
            }
        } catch {
            record.lastError = String(describing: error).prefix(1_000).description
            if record.attempts < 10 {
                record.status = .pending
                record.nextAttemptAt = Date(timeIntervalSinceNow: retryDelay(for: record.attempts))
            } else {
                record.status = .failed
            }
        }

        do {
            try await record.update(on: database)
        } catch {
            logger.error("Notification outbox update failed: \(error)")
        }
    }

    private static func retryDelay(for attempts: Int) -> TimeInterval {
        let exponent = min(max(attempts - 1, 0), 6)
        return TimeInterval(60 * (1 << exponent))
    }
}

enum TaskReminderService {
    /// Moves due reminders into the durable outbox. A reminder is marked as queued
    /// only after its event exists, so a failed insert remains available for retry.
    static func enqueueDueReminders(
        configuration: NotificationConfiguration,
        database: any Database,
        logger: Logger
    ) async {
        let reminders: [TaskReminder]
        do {
            reminders = try await TaskReminder.query(on: database)
                .filter(\.$queuedAt == nil)
                .filter(\.$remindAt <= Date())
                .with(\.$task) { task in
                    task.with(\.$board)
                }
                .with(\.$user)
                .sort(\.$remindAt, .ascending)
                .range(0..<20)
                .all()
        } catch {
            logger.error("Task reminder query failed: \(error)")
            return
        }

        for reminder in reminders {
            do {
                let event = try NotificationEvent.taskReminder(
                    reminder: reminder,
                    task: reminder.task,
                    board: reminder.task.board,
                    recipient: reminder.user,
                    appURL: configuration.publicAppURL
                )
                let alreadyQueued = try await NotificationOutbox.query(on: database)
                    .filter(\.$deduplicationKey == event.deduplicationKey)
                    .first() != nil
                if !alreadyQueued {
                    try await NotificationOutbox(event: event).create(on: database)
                }
                reminder.queuedAt = Date()
                try await reminder.update(on: database)
            } catch {
                logger.error("Task reminder enqueue failed: \(error)")
            }
        }
    }
}

enum PlanningBriefService {
    private struct BriefData {
        let studySessionCount: Int
        let plannedMinutes: Int
        let deadlineCount: Int
        let unplannedTaskCount: Int
        let remainingMinutes: Int
    }

    /// Enqueues at most one daily brief and one Monday planning prompt for each
    /// local calendar period. Outbox keys make late starts and repeated polls safe.
    static func enqueueDueBriefs(
        configuration: NotificationConfiguration,
        database: any Database,
        logger: Logger,
        referenceDate: Date = Date()
    ) async {
        let users: [User]
        do {
            users = try await User.query(on: database)
                .group(.or) { group in
                    group.filter(\.$dailyBriefEnabled == true)
                    group.filter(\.$weeklyPlanningPromptEnabled == true)
                }
                .all()
        } catch {
            logger.error("Planning brief user query failed: \(error)")
            return
        }

        for user in users {
            do {
                let calendar = planningCalendar(timeZoneIdentifier: user.timeZoneIdentifier)
                let localHour = calendar.component(.hour, from: referenceDate)
                guard localHour >= user.planningEmailHour else { continue }
                let dateKey = planningDateKey(referenceDate, calendar: calendar)
                let userID = try user.requireID()
                let dailyKey = "daily-brief:\(userID.uuidString):\(dateKey)"
                let isMonday = calendar.component(.weekday, from: referenceDate) == 2
                let weekStart = startOfWeek(containing: referenceDate, calendar: calendar)
                let weekKey = planningDateKey(weekStart, calendar: calendar)
                let weeklyKey = "weekly-planning:\(userID.uuidString):\(weekKey)"
                let dailyAlreadyQueued = if user.dailyBriefEnabled {
                    try await isQueued(dailyKey, on: database)
                } else {
                    false
                }
                let shouldCheckWeekly = user.weeklyPlanningPromptEnabled && isMonday
                let weeklyAlreadyQueued = if shouldCheckWeekly {
                    try await isQueued(weeklyKey, on: database)
                } else {
                    false
                }
                let needsDaily = user.dailyBriefEnabled && !dailyAlreadyQueued
                let needsWeekly = shouldCheckWeekly && !weeklyAlreadyQueued
                guard needsDaily || needsWeekly else { continue }

                let data = try await briefData(
                    user: user,
                    dateKey: dateKey,
                    database: database
                )
                guard !needsWeekly || data.unplannedTaskCount > 0 else { continue }
                if needsDaily {
                    let event = try NotificationEvent.dailyBrief(
                        user: user,
                        dateKey: dateKey,
                        dateLabel: planningDateLabel(
                            referenceDate,
                            format: "EEEE, MMMM d",
                            calendar: calendar
                        ),
                        studySessionCount: data.studySessionCount,
                        plannedMinutes: data.plannedMinutes,
                        deadlineCount: data.deadlineCount,
                        appURL: configuration.appURL(path: "/app")
                    )
                    try await NotificationOutbox(event: event).create(on: database)
                }
                if needsWeekly {
                    let event = try NotificationEvent.weeklyPlanningPrompt(
                        user: user,
                        weekKey: weekKey,
                        weekLabel: weekLabel(start: weekStart, calendar: calendar),
                        unplannedTaskCount: data.unplannedTaskCount,
                        remainingMinutes: data.remainingMinutes,
                        appURL: configuration.appURL(path: "/app")
                    )
                    try await NotificationOutbox(event: event).create(on: database)
                }
            } catch {
                logger.error("Planning brief enqueue failed: \(error)")
            }
        }
    }

    private static func briefData(
        user: User,
        dateKey: String,
        database: any Database
    ) async throws -> BriefData {
        let userID = try user.requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: database)
        let tasks = if boardIDs.isEmpty {
            [Task]()
        } else {
            try await Task.query(on: database)
                .filter(\.$board.$id ~~ boardIDs)
                .filter(\.$isArchived == false)
                .with(\.$board)
                .all()
        }
        let taskIDs = try tasks.map { try $0.requireID() }
        let sessions = if taskIDs.isEmpty {
            [StudySession]()
        } else {
            try await StudySession.query(on: database)
                .filter(\.$user.$id == userID)
                .filter(\.$task.$id ~~ taskIDs)
                .all()
        }
        let sessionsToday = sessions.filter { $0.scheduledDate == dateKey }
        let plannedMinutesByTask = Dictionary(grouping: sessions, by: \.$task.id)
            .mapValues { values in values.reduce(0) { $0 + $1.plannedMinutes } }
        var unplannedTaskCount = 0
        var remainingMinutes = 0
        for task in tasks where !task.board.isCompleted(task.status) {
            guard let taskID = task.id, let estimate = task.estimatedMinutes else { continue }
            let legacyMinutes = plannedMinutesByTask[taskID] == nil && task.startAt != nil ? estimate : 0
            let remaining = max(0, estimate - (plannedMinutesByTask[taskID] ?? 0) - legacyMinutes)
            if remaining > 0 {
                unplannedTaskCount += 1
                remainingMinutes += remaining
            }
        }
        let deadlineCount = tasks.filter {
            !$0.board.isCompleted($0.status) && $0.dueAt.map(inputDate) == dateKey
        }.count
        return BriefData(
            studySessionCount: sessionsToday.count,
            plannedMinutes: sessionsToday.reduce(0) { $0 + $1.plannedMinutes },
            deadlineCount: deadlineCount,
            unplannedTaskCount: unplannedTaskCount,
            remainingMinutes: remainingMinutes
        )
    }

    private static func isQueued(_ key: String, on database: any Database) async throws -> Bool {
        try await NotificationOutbox.query(on: database)
            .filter(\.$deduplicationKey == key)
            .first() != nil
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    private static func weekLabel(start: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startLabel = planningDateLabel(start, format: "MMM d", calendar: calendar)
        let endLabel = planningDateLabel(end, format: "MMM d", calendar: calendar)
        return startLabel + "–" + endLabel
    }
}

actor NotificationDispatchLoop {
    private var task: _Concurrency.Task<Void, Never>?
    private var nextBriefCheckAt = Date.distantPast

    func start(application: Application, configuration: NotificationConfiguration) {
        guard task == nil else { return }
        task = _Concurrency.Task {
            while !_Concurrency.Task.isCancelled {
                let now = Date()
                if now >= nextBriefCheckAt {
                    await PlanningBriefService.enqueueDueBriefs(
                        configuration: configuration,
                        database: application.db,
                        logger: application.logger,
                        referenceDate: now
                    )
                    nextBriefCheckAt = now.addingTimeInterval(60 * 60)
                }
                await TaskReminderService.enqueueDueReminders(
                    configuration: configuration,
                    database: application.db,
                    logger: application.logger
                )
                await NotificationService.dispatchPending(
                    configuration: configuration,
                    database: application.db,
                    client: application.client,
                    logger: application.logger
                )
                do {
                    try await _Concurrency.Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    func stop() async {
        task?.cancel()
        _ = await task?.value
        task = nil
    }
}

struct NotificationDispatchLifecycle: LifecycleHandler, Sendable {
    private let configuration: NotificationConfiguration
    private let loop = NotificationDispatchLoop()

    init(configuration: NotificationConfiguration) {
        self.configuration = configuration
    }

    func didBootAsync(_ application: Application) async throws {
        await loop.start(application: application, configuration: configuration)
    }

    func shutdownAsync(_ application: Application) async {
        await loop.stop()
    }
}

private struct WorkerNotificationRequest: Encodable, Sendable {
    let eventID: UUID
    let type: String
    let to: String
    let data: [String: String]
}

private struct WorkerNotificationResponse: Decodable, Sendable {
    let messageID: String

    enum CodingKeys: String, CodingKey {
        case messageID = "messageID"
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private struct NotificationConfigurationKey: StorageKey {
    typealias Value = NotificationConfiguration
}

extension Application {
    var notificationConfiguration: NotificationConfiguration? {
        get { storage[NotificationConfigurationKey.self] }
        set { storage[NotificationConfigurationKey.self] = newValue }
    }
}
