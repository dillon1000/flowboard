import Fluent
import Foundation
import Vapor

/// A user-owned block of planned work for one assignment. The date is stored as
/// a calendar key because it must not shift when the user or server changes zone.
final class StudySession: Model, @unchecked Sendable {
    static let schema = "study_sessions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: Task

    @Parent(key: "user_id")
    var user: User

    @Field(key: "scheduled_date")
    var scheduledDate: String

    @Field(key: "planned_minutes")
    var plannedMinutes: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        taskID: UUID,
        userID: UUID,
        scheduledDate: String,
        plannedMinutes: Int
    ) {
        self.id = id
        self.$task.id = taskID
        self.$user.id = userID
        self.scheduledDate = scheduledDate
        self.plannedMinutes = plannedMinutes
    }
}

struct CreateStudySessionRequest: Content, Validatable {
    let scheduledDate: String
    let plannedMinutes: Int

    static func validations(_ validations: inout Validations) {
        validations.add("scheduledDate", as: String.self, is: .count(10...10))
        validations.add("plannedMinutes", as: Int.self, is: .range(5...1_440))
    }
}

struct UpdateStudySessionRequest: Content {
    let scheduledDate: String?
    let plannedMinutes: Int?
}

struct AutoPlanStudySessionsRequest: Content, Validatable {
    let dailyLimitMinutes: Int
    let courseID: UUID?

    static func validations(_ validations: inout Validations) {
        validations.add("dailyLimitMinutes", as: Int.self, is: .range(30...1_440))
    }
}

struct StudySessionResponse: Content {
    let id: UUID
    let taskID: UUID
    let scheduledDate: String
    let plannedMinutes: Int
    let createdAt: Date?
    let updatedAt: Date?

    init(session: StudySession) throws {
        self.id = try session.requireID()
        self.taskID = session.$task.id
        self.scheduledDate = session.scheduledDate
        self.plannedMinutes = session.plannedMinutes
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
    }
}

struct AutoPlanStudySessionsResponse: Content {
    let createdSessionCount: Int
    let updatedSessionCount: Int
    let plannedMinutes: Int
    let remainingMinutes: Int
    let unplannedTaskCount: Int
}
