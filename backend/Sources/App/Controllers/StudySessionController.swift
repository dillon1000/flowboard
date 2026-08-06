import Fluent
import Foundation
import Vapor

/// Manages each user's private study plan while task access remains controlled by
/// the parent board. A viewer can plan personal work without editing the task.
struct StudySessionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let taskSessions = routes.grouped("tasks", ":taskID", "study-sessions")
        taskSessions.get(use: list)
        taskSessions.post(use: create)

        let sessions = routes.grouped("study-sessions")
        sessions.post("plan", use: autoPlan)
        sessions.post("repair", use: repair)
        sessions.post(":sessionID", "complete", use: complete)
        sessions.post(":sessionID", "skip", use: skip)
        sessions.patch(":sessionID", use: update)
        sessions.delete(":sessionID", use: delete)
    }

    func list(req: Request) async throws -> [StudySessionResponse] {
        let task = try await requiredTask(req)
        let userID = try req.auth.require(User.self).requireID()
        let sessions = try await StudySession.query(on: req.db)
            .filter(\.$task.$id == task.requireID())
            .filter(\.$user.$id == userID)
            .sort(\.$scheduledDate, .ascending)
            .all()
        return try sessions.map(StudySessionResponse.init)
    }

    func create(req: Request) async throws -> Response {
        try CreateStudySessionRequest.validate(content: req)
        let input = try req.content.decode(CreateStudySessionRequest.self)
        let task = try await requiredTask(req)
        let user = try req.auth.require(User.self)
        let scheduledDate = try validateDate(input.scheduledDate, user: user, task: task)
        try await validateTotal(
            input.plannedMinutes,
            task: task,
            user: user,
            excluding: nil,
            on: req.db
        )
        let session = StudySession(
            taskID: try task.requireID(),
            userID: try user.requireID(),
            scheduledDate: scheduledDate,
            plannedMinutes: input.plannedMinutes
        )
        do {
            try await session.create(on: req.db)
        } catch {
            throw Abort(.conflict, reason: "This assignment already has work planned on that date.")
        }
        return try await StudySessionResponse(session: session)
            .encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> StudySessionResponse {
        let input = try req.content.decode(UpdateStudySessionRequest.self)
        let user = try req.auth.require(User.self)
        let session = try await requiredSession(req, userID: user.requireID())
        let task = try await session.$task.get(on: req.db)
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: user.requireID(),
            permission: .view,
            on: req.db
        )
        guard session.state == .planned else {
            throw Abort(.conflict, reason: "Only a planned study session can move or change length.")
        }
        if let scheduledDate = input.scheduledDate {
            session.scheduledDate = try validateDate(scheduledDate, user: user, task: task)
        }
        if let plannedMinutes = input.plannedMinutes {
            guard (5...1_440).contains(plannedMinutes) else {
                throw Abort(.unprocessableEntity, reason: "Plan between 5 and 1440 minutes.")
            }
            session.plannedMinutes = plannedMinutes
        }
        try await validateTotal(
            session.plannedMinutes,
            task: task,
            user: user,
            excluding: session.requireID(),
            on: req.db
        )
        do {
            try await session.update(on: req.db)
        } catch {
            throw Abort(.conflict, reason: "This assignment already has work planned on that date.")
        }
        return try StudySessionResponse(session: session)
    }

    /// Records the time the student actually studied. Completion is final for
    /// this block, which prevents a retry from changing the student's history.
    func complete(req: Request) async throws -> StudySessionResponse {
        try CompleteStudySessionRequest.validate(content: req)
        let input = try req.content.decode(CompleteStudySessionRequest.self)
        let userID = try req.auth.require(User.self).requireID()
        let session = try await requiredSession(req, userID: userID)
        try await requireTaskAccess(for: session, userID: userID, on: req.db)
        guard session.state == .planned else {
            throw Abort(.conflict, reason: "Only a planned study session can be completed.")
        }
        session.state = .completed
        session.actualMinutes = input.actualMinutes
        session.completedAt = Date()
        try await session.update(on: req.db)
        return try StudySessionResponse(session: session)
    }

    /// Keeps a skipped block as planning history while returning its work to the
    /// assignment estimate for the next plan or repair.
    func skip(req: Request) async throws -> StudySessionResponse {
        let userID = try req.auth.require(User.self).requireID()
        let session = try await requiredSession(req, userID: userID)
        try await requireTaskAccess(for: session, userID: userID, on: req.db)
        guard session.state == .planned else {
            throw Abort(.conflict, reason: "Only a planned study session can be skipped.")
        }
        session.state = .skipped
        session.actualMinutes = nil
        session.completedAt = nil
        try await session.update(on: req.db)
        return try StudySessionResponse(session: session)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let userID = try req.auth.require(User.self).requireID()
        let session = try await requiredSession(req, userID: userID)
        let task = try await session.$task.get(on: req.db)
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: userID,
            permission: .view,
            on: req.db
        )
        try await session.delete(on: req.db)
        return .noContent
    }

    /// Applies the pure allocator in one transaction. Each allocation is added to
    /// an existing task-date block or creates one, so the unique key is preserved.
    func autoPlan(req: Request) async throws -> AutoPlanStudySessionsResponse {
        try AutoPlanStudySessionsRequest.validate(content: req)
        let input = try req.content.decode(AutoPlanStudySessionsRequest.self)
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        if let courseID = input.courseID {
            guard boardIDs.contains(courseID) else {
                throw Abort(.notFound, reason: "The course does not exist.")
            }
        }
        let allTasks = try await Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .with(\.$board)
            .all()
            .filter { !$0.board.isCompleted($0.status) }
        let tasks = input.courseID.map { courseID in
            allTasks.filter { $0.$board.id == courseID }
        } ?? allTasks
        let taskIDs = try allTasks.map { try $0.requireID() }
        let sessions = if taskIDs.isEmpty {
            [StudySession]()
        } else {
            try await StudySession.query(on: req.db)
                .filter(\.$user.$id == userID)
                .filter(\.$task.$id ~~ taskIDs)
                .all()
        }
        let planningTasks = tasks.compactMap { task -> StudyPlanningTask? in
            guard
                let taskID = task.id,
                let estimatedMinutes = task.estimatedMinutes
            else {
                return nil
            }
            return StudyPlanningTask(
                id: taskID,
                dueDate: task.dueAt.map(inputDate) ?? "9999-12-31",
                estimatedMinutes: estimatedMinutes,
                priority: task.priorityValue
            )
        }
        let sessionTaskIDs = Set(sessions.map(\.$task.id))
        let planningSessions = sessions.map {
            StudyPlanningSession(
                taskID: $0.$task.id,
                scheduledDate: $0.scheduledDate,
                plannedMinutes: $0.plannedMinutes,
                state: $0.state,
                actualMinutes: $0.actualMinutes
            )
        } + allTasks.compactMap { task -> StudyPlanningSession? in
            guard
                let taskID = task.id,
                let startAt = task.startAt,
                let estimatedMinutes = task.estimatedMinutes,
                !sessionTaskIDs.contains(taskID)
            else {
                return nil
            }
            // Before study sessions existed, the weekly planner stored one work
            // day in startAt. Count that legacy plan until the task is rescheduled.
            return StudyPlanningSession(
                taskID: taskID,
                scheduledDate: inputDate(startAt),
                plannedMinutes: estimatedMinutes,
                state: .planned,
                actualMinutes: nil
            )
        }
        let settings = try await StudySettings.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        let availability = input.dailyLimitMinutes.map(StudyAvailability.init(dailyLimitMinutes:))
            ?? StudyAvailability(settings: settings)
        let result = StudyPlanningService.plan(
            tasks: planningTasks,
            sessions: planningSessions,
            availability: availability,
            timeZoneIdentifier: user.timeZoneIdentifier
        )

        let (createdSessionCount, updatedSessionCount) = try await req.db.transaction { database in
            try await persist(
                allocations: result.allocations,
                userID: userID,
                on: database
            )
        }
        return AutoPlanStudySessionsResponse(
            createdSessionCount: createdSessionCount,
            updatedSessionCount: updatedSessionCount,
            plannedMinutes: result.allocations.reduce(0) { $0 + $1.plannedMinutes },
            remainingMinutes: result.remainingMinutes,
            unplannedTaskCount: result.unplannedTaskCount
        )
    }

    /// Returns missed, invalid, and overloaded plans to the queue, then runs the
    /// allocator once with the student's current availability.
    func repair(req: Request) async throws -> RepairStudyWeekResponse {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        let allTasks = try await Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .filter(\.$isArchived == false)
            .with(\.$board)
            .all()
            .filter { !$0.board.isCompleted($0.status) }
        let taskIDs = try allTasks.map { try $0.requireID() }
        let sessions = taskIDs.isEmpty ? [] : try await StudySession.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$task.$id ~~ taskIDs)
            .all()
        let settings = try await StudySettings.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        let availability = StudyAvailability(settings: settings)
        let dueDateByTaskID = Dictionary(
            uniqueKeysWithValues: allTasks.compactMap { task -> (UUID, String)? in
                guard let taskID = task.id, let dueAt = task.dueAt else { return nil }
                return (taskID, inputDate(dueAt))
            }
        )
        let analysis = StudyRecoveryService.analyze(
            sessions: sessions,
            dueDateByTaskID: dueDateByTaskID,
            availability: availability,
            timeZoneIdentifier: user.timeZoneIdentifier
        )
        let affectedSessions = sessions.filter { session in
            session.id.map(analysis.affectedSessionIDs.contains) ?? false
        }
        for session in affectedSessions {
            session.state = .skipped
            session.actualMinutes = nil
            session.completedAt = nil
        }
        if !analysis.affectedSessionIDs.isEmpty {
            try await req.db.transaction { database in
                for session in affectedSessions {
                    try await session.update(on: database)
                }
            }
        }

        let planningTasks = allTasks.compactMap { task -> StudyPlanningTask? in
            guard let taskID = task.id, let estimatedMinutes = task.estimatedMinutes else { return nil }
            return StudyPlanningTask(
                id: taskID,
                dueDate: task.dueAt.map(inputDate) ?? "9999-12-31",
                estimatedMinutes: estimatedMinutes,
                priority: task.priorityValue
            )
        }
        let planningSessions = sessions.map {
            StudyPlanningSession(
                taskID: $0.$task.id,
                scheduledDate: $0.scheduledDate,
                plannedMinutes: $0.plannedMinutes,
                state: $0.state,
                actualMinutes: $0.actualMinutes
            )
        }
        let result = StudyPlanningService.plan(
            tasks: planningTasks,
            sessions: planningSessions,
            availability: availability,
            timeZoneIdentifier: user.timeZoneIdentifier
        )
        let (createdCount, updatedCount) = try await req.db.transaction { database in
            try await persist(allocations: result.allocations, userID: userID, on: database)
        }
        return RepairStudyWeekResponse(
            repairedSessionCount: analysis.affectedSessionIDs.count,
            createdSessionCount: createdCount,
            updatedSessionCount: updatedCount,
            plannedMinutes: result.allocations.reduce(0) { $0 + $1.plannedMinutes },
            remainingMinutes: result.remainingMinutes,
            unplannedTaskCount: result.unplannedTaskCount
        )
    }

    /// Reuses skipped rows because the task-user-date key is unique. Completed
    /// rows remain immutable evidence and are never converted back into plans.
    private func persist(
        allocations: [StudySessionAllocation],
        userID: UUID,
        on database: any Database
    ) async throws -> (created: Int, updated: Int) {
        var createdCount = 0
        var updatedCount = 0
        for allocation in allocations {
            if let existing = try await StudySession.query(on: database)
                .filter(\.$task.$id == allocation.taskID)
                .filter(\.$user.$id == userID)
                .filter(\.$scheduledDate == allocation.scheduledDate)
                .first()
            {
                guard existing.state != .completed else { continue }
                if existing.state == .skipped {
                    existing.plannedMinutes = allocation.plannedMinutes
                    existing.state = .planned
                    existing.actualMinutes = nil
                    existing.completedAt = nil
                } else {
                    existing.plannedMinutes += allocation.plannedMinutes
                }
                try await existing.update(on: database)
                updatedCount += 1
            } else {
                try await StudySession(
                    taskID: allocation.taskID,
                    userID: userID,
                    scheduledDate: allocation.scheduledDate,
                    plannedMinutes: allocation.plannedMinutes
                ).create(on: database)
                createdCount += 1
            }
        }
        return (createdCount, updatedCount)
    }

    private func requiredTask(_ req: Request) async throws -> Task {
        guard
            let taskID = req.parameters.get("taskID", as: UUID.self),
            let task = try await Task.find(taskID, on: req.db)
        else {
            throw Abort(.notFound, reason: "The assignment does not exist.")
        }
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: req.auth.require(User.self).requireID(),
            permission: .view,
            on: req.db
        )
        return task
    }

    private func requiredSession(_ req: Request, userID: UUID) async throws -> StudySession {
        guard
            let sessionID = req.parameters.get("sessionID", as: UUID.self),
            let session = try await StudySession.query(on: req.db)
                .filter(\.$id == sessionID)
                .filter(\.$user.$id == userID)
                .first()
        else {
            throw Abort(.notFound, reason: "The study session does not exist.")
        }
        return session
    }

    private func requireTaskAccess(
        for session: StudySession,
        userID: UUID,
        on database: any Database
    ) async throws {
        let task = try await session.$task.get(on: database)
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: userID,
            permission: .view,
            on: database
        )
    }

    private func validateDate(_ value: String, user: User, task: Task) throws -> String {
        let calendar = planningCalendar(timeZoneIdentifier: user.timeZoneIdentifier)
        guard
            value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
            let date = planningDate(value, calendar: calendar),
            planningDateKey(date, calendar: calendar) == value
        else {
            throw Abort(.unprocessableEntity, reason: "Choose a valid study date.")
        }
        let todayKey = planningDateKey(Date(), calendar: calendar)
        guard value >= todayKey else {
            throw Abort(.unprocessableEntity, reason: "Choose today or a future date.")
        }
        if let dueAt = task.dueAt, value > max(todayKey, inputDate(dueAt)) {
            throw Abort(.unprocessableEntity, reason: "Plan the work on or before its deadline.")
        }
        return value
    }

    private func validateTotal(
        _ plannedMinutes: Int,
        task: Task,
        user: User,
        excluding sessionID: UUID?,
        on database: any Database
    ) async throws {
        guard let estimate = task.estimatedMinutes, estimate > 0 else {
            throw Abort(.unprocessableEntity, reason: "Add a time estimate before planning work.")
        }
        let taskID = try task.requireID()
        let userID = try user.requireID()
        let todayKey = planningDateKey(
            Date(),
            calendar: planningCalendar(timeZoneIdentifier: user.timeZoneIdentifier)
        )
        var query = StudySession.query(on: database)
            .filter(\.$task.$id == taskID)
            .filter(\.$user.$id == userID)
        if let sessionID {
            query = query.filter(\.$id != sessionID)
        }
        let existingMinutes = try await query.all().reduce(0) { total, session in
            switch session.state {
            case .completed:
                total + (session.actualMinutes ?? session.plannedMinutes)
            case .planned where session.scheduledDate >= todayKey:
                total + session.plannedMinutes
            default:
                total
            }
        }
        guard existingMinutes + plannedMinutes <= estimate else {
            throw Abort(.unprocessableEntity, reason: "Planned work cannot exceed the task estimate.")
        }
    }
}
