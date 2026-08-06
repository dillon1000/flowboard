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

    /// Renders stable timed study blocks and deadline events. Local planning
    /// times are converted to UTC so clients need no custom VTIMEZONE definition.
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
        let totalMinutesByDate = Dictionary(grouping: sessions, by: \.scheduledDate)
            .mapValues { values in values.reduce(0) { $0 + $1.plannedMinutes } }
        var nextStartMinuteByDate = totalMinutesByDate.mapValues { totalMinutes in
            min(18 * 60, max(0, 24 * 60 - totalMinutes))
        }
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
            let alarmTrigger: String
            if let dueDate = timedDeadline(task: task, dateKey: dateKey, calendar: calendar) {
                lines.append("DTSTART:\(timestamp(dueDate))")
                alarmTrigger = "-PT1H"
            } else {
                lines.append("DTSTART;VALUE=DATE:\(compactDate(dateKey))")
                alarmTrigger = "-P1D"
            }
            lines.append("SUMMARY:\(escapeText("Due: \(task.title)"))")
            lines.append("DESCRIPTION:\(escapeText("Course: \(task.board.name)"))")
            lines.append("STATUS:CONFIRMED")
            lines.append("BEGIN:VALARM")
            lines.append("TRIGGER:\(alarmTrigger)")
            lines.append("ACTION:DISPLAY")
            lines.append("DESCRIPTION:\(escapeText("Deadline: \(task.title)"))")
            lines.append("END:VALARM")
            lines.append("END:VEVENT")
        }

        for session in sessions.sorted(by: {
            if $0.scheduledDate != $1.scheduledDate {
                return $0.scheduledDate < $1.scheduledDate
            }
            return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }) {
            guard let sessionID = session.id, let task = taskByID[session.$task.id] else { continue }
            let startMinute = nextStartMinuteByDate[session.scheduledDate] ?? 18 * 60
            guard let start = studySessionStart(
                dateKey: session.scheduledDate,
                minuteOfDay: startMinute,
                calendar: calendar
            ), let end = calendar.date(byAdding: .minute, value: session.plannedMinutes, to: start)
            else { continue }
            nextStartMinuteByDate[session.scheduledDate] = startMinute + session.plannedMinutes
            lines.append("BEGIN:VEVENT")
            lines.append("UID:study-session-\(sessionID.uuidString.lowercased())@focalpoint")
            lines.append("DTSTAMP:\(timestamp(session.updatedAt ?? session.createdAt ?? Date()))")
            lines.append("DTSTART:\(timestamp(start))")
            lines.append("DTEND:\(timestamp(end))")
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

    /// Places each date's study work sequentially from 6:00 PM. If the total
    /// duration cannot fit before midnight, the first block moves earlier.
    private static func studySessionStart(
        dateKey: String,
        minuteOfDay: Int,
        calendar: Calendar
    ) -> Date? {
        guard let date = planningDate(dateKey, calendar: calendar) else { return nil }
        return calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: date
        )
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
