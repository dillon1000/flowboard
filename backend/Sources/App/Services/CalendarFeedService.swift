import Crypto
import Fluent
import Foundation
import Vapor

enum CalendarFeedService {
    static let tokenPrefix = "fbc_"

    /// Creates a 256-bit URL-safe token. Only its digest and visible prefix are
    /// persisted; the raw value exists long enough to build the subscription URL.
    static func rotate(
        userID: UUID,
        on database: any Database
    ) async throws -> (credential: CalendarFeedCredential, raw: String) {
        let generated = generate()
        let credential: CalendarFeedCredential
        if let existing = try await CalendarFeedCredential.query(on: database)
            .filter(\.$user.$id == userID)
            .first()
        {
            existing.tokenHash = generated.hash
            existing.tokenPrefix = generated.visiblePrefix
            try await existing.update(on: database)
            credential = existing
        } else {
            let created = CalendarFeedCredential(
                userID: userID,
                tokenHash: generated.hash,
                tokenPrefix: generated.visiblePrefix
            )
            try await created.create(on: database)
            credential = created
        }
        return (credential, generated.raw)
    }

    static func authenticate(
        _ rawToken: String,
        on database: any Database
    ) async throws -> CalendarFeedCredential? {
        guard rawToken.hasPrefix(tokenPrefix), rawToken.count == tokenPrefix.count + 64 else {
            return nil
        }
        return try await CalendarFeedCredential.query(on: database)
            .filter(\.$tokenHash == hash(rawToken))
            .with(\.$user)
            .first()
    }

    /// Renders stable all-day study blocks and deadline events. Timed deadlines
    /// are converted from the user's local zone to UTC so clients need no custom
    /// VTIMEZONE definition.
    static func response(
        credential: CalendarFeedCredential,
        on database: any Database
    ) async throws -> Response {
        let user = credential.user
        let userID = try user.requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: database)
        let tasks = try await Task.query(on: database)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .with(\.$board)
            .all()
        let taskIDs = try tasks.map { try $0.requireID() }
        let sessions = if taskIDs.isEmpty {
            [StudySession]()
        } else {
            try await StudySession.query(on: database)
                .filter(\.$user.$id == userID)
                .filter(\.$task.$id ~~ taskIDs)
                .all()
        }
        let taskByID = Dictionary(uniqueKeysWithValues: try tasks.map { (try $0.requireID(), $0) })
        let calendar = planningCalendar(timeZoneIdentifier: user.timeZoneIdentifier)
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Focalpoint//Study Calendar//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:Focalpoint Study Plan",
            "X-WR-TIMEZONE:\(escapeText(user.timeZoneIdentifier))",
        ]

        for task in tasks.sorted(by: { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }) {
            guard let taskID = task.id, let dueAt = task.dueAt else { continue }
            let dateKey = inputDate(dueAt)
            lines.append("BEGIN:VEVENT")
            lines.append("UID:task-\(taskID.uuidString.lowercased())@focalpoint")
            lines.append("DTSTAMP:\(timestamp(task.updatedAt ?? task.createdAt ?? Date()))")
            if let dueDate = timedDeadline(task: task, dateKey: dateKey, calendar: calendar) {
                lines.append("DTSTART:\(timestamp(dueDate))")
            } else {
                lines.append("DTSTART;VALUE=DATE:\(compactDate(dateKey))")
            }
            lines.append("SUMMARY:\(escapeText("Due: \(task.title)"))")
            lines.append("DESCRIPTION:\(escapeText("Course: \(task.board.name)"))")
            lines.append("STATUS:CONFIRMED")
            lines.append("END:VEVENT")
        }

        for session in sessions.sorted(by: { $0.scheduledDate < $1.scheduledDate }) {
            guard let sessionID = session.id, let task = taskByID[session.$task.id] else { continue }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:study-session-\(sessionID.uuidString.lowercased())@focalpoint")
            lines.append("DTSTAMP:\(timestamp(session.updatedAt ?? session.createdAt ?? Date()))")
            lines.append("DTSTART;VALUE=DATE:\(compactDate(session.scheduledDate))")
            lines.append("SUMMARY:\(escapeText("Study: \(task.title)"))")
            lines.append(
                "DESCRIPTION:\(escapeText("\(displayDuration(session.plannedMinutes)) planned · \(task.board.name)"))"
            )
            lines.append("STATUS:CONFIRMED")
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")

        let body = lines.flatMap(foldLine).joined(separator: "\r\n") + "\r\n"
        var headers = HTTPHeaders()
        headers.contentType = HTTPMediaType(
            type: "text",
            subType: "calendar",
            parameters: ["charset": "utf-8"]
        )
        headers.replaceOrAdd(name: .contentDisposition, value: "inline; filename=\"focalpoint.ics\"")
        headers.cacheControl = .init(noStore: true, isPrivate: true)
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }

    private static func generate() -> (raw: String, hash: String, visiblePrefix: String) {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let raw = tokenPrefix + bytes.map(hex).joined()
        return (raw, hash(raw), String(raw.prefix(12)))
    }

    private static func hash(_ rawToken: String) -> String {
        SHA256.hash(data: Data(rawToken.utf8)).map(hex).joined()
    }

    private static func hex(_ byte: UInt8) -> String {
        String(format: "%02x", byte)
    }

    private static func compactDate(_ dateKey: String) -> String {
        dateKey.replacingOccurrences(of: "-", with: "")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func timedDeadline(
        task: Task,
        dateKey: String,
        calendar: Calendar
    ) -> Date? {
        guard
            let dueTime = task.dueTime,
            let date = planningDate(dateKey, calendar: calendar)
        else {
            return nil
        }
        let parts = dueTime.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    /// RFC 5545 limits content lines to 75 UTF-8 octets. Continuation lines start
    /// with one space, so they have room for 74 data octets.
    private static func foldLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        let limit = 75
        for character in line {
            let value = String(character)
            if !current.isEmpty, current.utf8.count + value.utf8.count > limit {
                result.append(current)
                current = " " + value
            } else {
                current += value
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
