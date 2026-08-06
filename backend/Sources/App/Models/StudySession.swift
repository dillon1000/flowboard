import Fluent
import Foundation
import Vapor

/// A string-backed lifecycle keeps stored values and API responses stable while
/// the interface gives each transition a specific action.
struct StudySessionState: Codable, Content, Hashable, Sendable {
    let rawValue: String

    static let planned = Self(rawValue: "planned")
    static let completed = Self(rawValue: "completed")
    static let skipped = Self(rawValue: "skipped")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

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

    @Field(key: "state")
    var stateValue: String

    @OptionalField(key: "actual_minutes")
    var actualMinutes: Int?

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    var state: StudySessionState {
        get { StudySessionState(rawValue: stateValue) }
        set { stateValue = newValue.rawValue }
    }

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
        plannedMinutes: Int,
        state: StudySessionState = .planned,
        actualMinutes: Int? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.$task.id = taskID
        self.$user.id = userID
        self.scheduledDate = scheduledDate
        self.plannedMinutes = plannedMinutes
        self.stateValue = state.rawValue
        self.actualMinutes = actualMinutes
        self.completedAt = completedAt
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
    let dailyLimitMinutes: Int?
    let courseID: UUID?

    static func validations(_ validations: inout Validations) {
        validations.add(
            "dailyLimitMinutes",
            as: Int.self,
            is: .range(30...1_440),
            required: false
        )
    }
}

struct CompleteStudySessionRequest: Content, Validatable {
    let actualMinutes: Int

    static func validations(_ validations: inout Validations) {
        validations.add("actualMinutes", as: Int.self, is: .range(1...1_440))
    }
}

struct StudySessionResponse: Content {
    let id: UUID
    let taskID: UUID
    let scheduledDate: String
    let plannedMinutes: Int
    let state: StudySessionState
    let actualMinutes: Int?
    let completedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init(session: StudySession) throws {
        self.id = try session.requireID()
        self.taskID = session.$task.id
        self.scheduledDate = session.scheduledDate
        self.plannedMinutes = session.plannedMinutes
        self.state = session.state
        self.actualMinutes = session.actualMinutes
        self.completedAt = session.completedAt
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

struct RepairStudyWeekResponse: Content {
    let repairedSessionCount: Int
    let createdSessionCount: Int
    let updatedSessionCount: Int
    let plannedMinutes: Int
    let remainingMinutes: Int
    let unplannedTaskCount: Int
}
