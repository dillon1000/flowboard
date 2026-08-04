import Crypto
import Fluent
import Foundation
import Vapor

enum NotificationType: String, Codable, Sendable {
    case welcome
    case boardMemberAdded = "board_member_added"
    case taskCommentAdded = "task_comment_added"
    case taskAssigned = "task_assigned"
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

    static func taskAssigned(
        task: Task,
        board: Board,
        assignee: User,
        actor: User,
        appURL: String
    ) throws -> Self {
        let taskID = try task.requireID()
        let assigneeID = try assignee.requireID()
        return Self(
            deduplicationKey: "task-assignment:\(UUID().uuidString)",
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

actor NotificationDispatchLoop {
    private var task: Task<Void, Never>?

    func start(application: Application, configuration: NotificationConfiguration) {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                await NotificationService.dispatchPending(
                    configuration: configuration,
                    database: application.db,
                    client: application.client,
                    logger: application.logger
                )
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
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
