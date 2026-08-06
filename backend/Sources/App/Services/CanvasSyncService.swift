import Fluent
import Foundation
import Vapor

enum CanvasSyncService {
    private static let completedStates: Set<String> = [
        "submitted",
        "graded",
        "pending_review",
        "excused",
    ]

    /// Applies one validated snapshot in a single transaction. Duplicate snapshots
    /// return from the transaction without changing connection or workspace data.
    static func sync(
        _ snapshot: CanvasSyncSnapshotV1,
        connection authenticatedConnection: CanvasConnection,
        on database: any Database
    ) async throws -> CanvasSyncResponse {
        try snapshot.validate(expectedOrigin: authenticatedConnection.canvasOrigin)
        let connectionID = try authenticatedConnection.requireID()
        let syncedAt = Date()

        return try await database.transaction { transaction in
            guard let connection = try await CanvasConnection.find(connectionID, on: transaction) else {
                throw Abort(.unauthorized, reason: "Canvas connection no longer exists.")
            }
            if connection.lastSnapshotID == snapshot.snapshotID {
                return CanvasSyncResponse(
                    snapshotID: snapshot.snapshotID,
                    duplicate: true,
                    capturedAt: snapshot.capturedAt,
                    syncedAt: connection.lastSuccessfulSyncAt ?? syncedAt,
                    counts: CanvasSyncCounts()
                )
            }
            if let lastCapturedAt = connection.lastCapturedAt,
               snapshot.capturedAt < lastCapturedAt {
                throw Abort(.conflict, reason: "Canvas snapshot is older than the last successful snapshot.")
            }
            guard let user = try await User.find(connection.$user.id, on: transaction) else {
                throw Abort(.unauthorized, reason: "Canvas connection owner no longer exists.")
            }

            var counts = CanvasSyncCounts()
            var coursesByRemoteID = Dictionary(
                uniqueKeysWithValues: try await CanvasCourseLink.query(on: transaction)
                    .filter(\.$connection.$id == connectionID)
                    .with(\.$board)
                    .all()
                    .map { ($0.remoteCourseID, $0) }
            )

            for courseSnapshot in snapshot.courses {
                let courseLink: CanvasCourseLink
                let board: Board
                if let existing = coursesByRemoteID.removeValue(forKey: courseSnapshot.id) {
                    courseLink = existing
                    board = existing.board
                    counts.coursesUpdated += 1
                    if courseLink.syncArchived {
                        board.isArchived = false
                        courseLink.syncArchived = false
                    }
                } else {
                    board = try await WorkspaceService.createBoard(
                        name: courseSnapshot.name,
                        slug: try await uniqueCourseSlug(
                            name: courseSnapshot.name,
                            remoteID: courseSnapshot.id,
                            on: transaction
                        ),
                        ownerID: try user.requireID(),
                        on: transaction
                    )
                    courseLink = CanvasCourseLink(
                        connectionID: connectionID,
                        remoteCourseID: courseSnapshot.id,
                        boardID: try board.requireID(),
                        canvasCourseURL: courseSnapshot.htmlURL
                    )
                    try await courseLink.create(on: transaction)
                    counts.coursesCreated += 1
                }

                board.name = courseSnapshot.name
                courseLink.canvasCourseURL = courseSnapshot.htmlURL
                courseLink.courseCode = clean(courseSnapshot.courseCode)
                courseLink.termName = clean(courseSnapshot.termName)
                courseLink.currentScore = courseSnapshot.currentScore
                courseLink.currentGrade = clean(courseSnapshot.currentGrade)
                courseLink.consecutiveMissingCount = 0
                try await board.update(on: transaction)
                try await courseLink.update(on: transaction)

                try await syncAssignments(
                    courseSnapshot.assignments,
                    courseLink: courseLink,
                    board: board,
                    user: user,
                    counts: &counts,
                    on: transaction
                )
            }

            for missingCourse in coursesByRemoteID.values {
                try await markCourseMissing(missingCourse, counts: &counts, on: transaction)
            }

            connection.lastSnapshotID = snapshot.snapshotID
            connection.lastCapturedAt = snapshot.capturedAt
            connection.lastSuccessfulSyncAt = syncedAt
            connection.lastErrorSummary = nil
            try await connection.update(on: transaction)

            return CanvasSyncResponse(
                snapshotID: snapshot.snapshotID,
                duplicate: false,
                capturedAt: snapshot.capturedAt,
                syncedAt: syncedAt,
                counts: counts
            )
        }
    }

    /// Updates source-owned assignment fields and keeps all local planning fields intact.
    private static func syncAssignments(
        _ snapshots: [CanvasAssignmentSnapshot],
        courseLink: CanvasCourseLink,
        board: Board,
        user: User,
        counts: inout CanvasSyncCounts,
        on database: any Database
    ) async throws {
        let courseLinkID = try courseLink.requireID()
        var linksByRemoteID = Dictionary(
            uniqueKeysWithValues: try await CanvasAssignmentLink.query(on: database)
                .filter(\.$courseLink.$id == courseLinkID)
                .with(\.$task)
                .all()
                .map { ($0.remoteAssignmentID, $0) }
        )

        for snapshot in snapshots {
            let link: CanvasAssignmentLink
            let task: Task
            if let existing = linksByRemoteID.removeValue(forKey: snapshot.id) {
                link = existing
                task = existing.task
                counts.assignmentsUpdated += 1
                if link.syncArchived {
                    task.isArchived = false
                    link.syncArchived = false
                }
            } else {
                let backlogCount = try await Task.query(on: database)
                    .filter(\.$board.$id == board.requireID())
                    .filter(\.$statusValue == TaskStatus.backlog.rawValue)
                    .count()
                task = Task(
                    publicID: try await Task.uniquePublicID(on: database),
                    boardID: try board.requireID(),
                    title: snapshot.name,
                    status: .backlog,
                    position: (backlogCount + 1) * 1_000,
                    creatorID: try user.requireID()
                )
                try await task.create(on: database)
                link = CanvasAssignmentLink(
                    courseLinkID: courseLinkID,
                    remoteAssignmentID: snapshot.id,
                    taskID: try task.requireID(),
                    canvasAssignmentURL: snapshot.htmlURL
                )
                try await link.create(on: database)
                counts.assignmentsCreated += 1
            }

            let due = localDueFields(snapshot.dueAt, timeZoneIdentifier: user.timeZoneIdentifier)
            task.title = snapshot.name
            task.description = clean(snapshot.descriptionText)
            task.dueAt = due.date
            task.dueTime = due.time
            task.gradePossible = snapshot.pointsPossible
            task.gradeEarned = snapshot.submission?.score

            link.canvasAssignmentURL = snapshot.htmlURL
            link.submissionState = clean(snapshot.submission?.workflowState)
            link.gradeLabel = clean(snapshot.submission?.grade)
            link.submittedAt = snapshot.submission?.submittedAt
            link.isLate = snapshot.submission?.late ?? false
            link.isMissing = snapshot.submission?.missing ?? false
            link.isExcused = snapshot.submission?.excused ?? false
            link.redoRequested = snapshot.submission?.redoRequested ?? false
            link.consecutiveMissingCount = 0
            applyCompletion(
                submission: snapshot.submission,
                link: link,
                task: task,
                board: board,
                counts: &counts
            )

            try await task.update(on: database)
            try await link.update(on: database)
        }

        for missingLink in linksByRemoteID.values {
            try await markAssignmentMissing(
                missingLink,
                task: missingLink.task,
                counts: &counts,
                on: database
            )
        }
    }

    /// Canvas completion remains authoritative on every later snapshot. The saved
    /// local status is captured only when Canvas first takes control.
    private static func applyCompletion(
        submission: CanvasSubmissionSnapshot?,
        link: CanvasAssignmentLink,
        task: Task,
        board: Board,
        counts: inout CanvasSyncCounts
    ) {
        let sourceIsComplete = if let submission {
            !submission.redoRequested
                && (submission.excused
                    || completedStates.contains(submission.workflowState?.lowercased() ?? ""))
        } else {
            false
        }

        if sourceIsComplete {
            if !link.canvasControlsCompletion {
                link.statusBeforeCanvasCompletion = board.isCompleted(task.status)
                    ? nil
                    : task.status.rawValue
                link.canvasControlsCompletion = true
            }
            if let completion = board.taskStatuses.first(where: \.isCompleted),
               task.statusValue != completion.id {
                task.statusValue = completion.id
                counts.assignmentsCompleted += 1
            }
            return
        }

        guard link.canvasControlsCompletion else { return }
        let savedStatus = link.statusBeforeCanvasCompletion.flatMap { savedID in
            board.taskStatuses.first { $0.id == savedID && !$0.isCompleted }
        }
        if let reopenedStatus = savedStatus ?? board.taskStatuses.first(where: { !$0.isCompleted }),
           task.statusValue != reopenedStatus.id {
            task.statusValue = reopenedStatus.id
            counts.assignmentsReopened += 1
        }
        link.statusBeforeCanvasCompletion = nil
        link.canvasControlsCompletion = false
    }

    private static func markCourseMissing(
        _ link: CanvasCourseLink,
        counts: inout CanvasSyncCounts,
        on database: any Database
    ) async throws {
        let board = link.board
        link.consecutiveMissingCount += 1
        if link.consecutiveMissingCount >= 2, !board.isArchived {
            board.isArchived = true
            link.syncArchived = true
            counts.coursesArchived += 1
            try await board.update(on: database)
        }
        try await link.update(on: database)

        let assignments = try await CanvasAssignmentLink.query(on: database)
            .filter(\.$courseLink.$id == link.requireID())
            .with(\.$task)
            .all()
        for assignment in assignments {
            try await markAssignmentMissing(
                assignment,
                task: assignment.task,
                counts: &counts,
                on: database
            )
        }
    }

    private static func markAssignmentMissing(
        _ link: CanvasAssignmentLink,
        task: Task,
        counts: inout CanvasSyncCounts,
        on database: any Database
    ) async throws {
        link.consecutiveMissingCount += 1
        if link.consecutiveMissingCount >= 2, !task.isArchived {
            task.isArchived = true
            link.syncArchived = true
            counts.assignmentsArchived += 1
            try await task.update(on: database)
        }
        try await link.update(on: database)
    }

    /// Stores the local calendar date at UTC midnight and the local clock separately.
    private static func localDueFields(
        _ dueAt: Date?,
        timeZoneIdentifier: String
    ) -> (date: Date?, time: String?) {
        guard let dueAt else { return (nil, nil) }
        let localCalendar = planningCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let components = localCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueAt
        )
        var UTCCalendar = Calendar(identifier: .gregorian)
        UTCCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = UTCCalendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day
        ))
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        return (date, time)
    }

    private static func uniqueCourseSlug(
        name: String,
        remoteID: String,
        on database: any Database
    ) async throws -> String {
        let normalizedName = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let normalizedID = remoteID.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = String("canvas-\(normalizedName.isEmpty ? "course" : normalizedName)-\(normalizedID)".prefix(48))
        guard try await Board.query(on: database).filter(\.$slug == base).first() != nil else {
            return base
        }
        return "\(String(base.prefix(39)))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
