import Fluent
import Foundation
import Vapor

struct StudyRecurringCommitment: Codable, Content, Equatable, Sendable {
    let id: String
    let title: String
    let kind: String
    let weekdays: [Int]
    let startTime: String
    let endTime: String
}

struct StudyCalendarConflict: Codable, Content, Equatable, Sendable {
    let id: String
    let title: String
    let date: String
    let startTime: String
    let endTime: String
}

struct StudyEstimatePreset: Codable, Content, Equatable, Sendable {
    let id: String
    let name: String
    let minutes: Int
    let keywords: [String]

    static let defaults = [
        Self(id: "reading", name: "Reading", minutes: 45, keywords: ["reading", "read", "chapter"]),
        Self(id: "lab", name: "Lab", minutes: 120, keywords: ["lab"]),
        Self(id: "problem-set", name: "Problem set", minutes: 90, keywords: ["problem set", "worksheet"]),
        Self(id: "essay", name: "Essay", minutes: 120, keywords: ["essay", "paper"]),
    ]
}

/// One user-owned record keeps every input that changes weekly allocation in a
/// single transaction. Capacities are gross study minutes; commitments and
/// conflicts are subtracted when the planner calculates each date.
final class StudySettings: Model, @unchecked Sendable {
    static let schema = "study_settings"

    static let defaultWeekdayCapacityMinutes = [
        "monday": 120,
        "tuesday": 120,
        "wednesday": 120,
        "thursday": 120,
        "friday": 120,
        "saturday": 180,
        "sunday": 180,
    ]

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "weekday_capacity_minutes")
    var weekdayCapacityMinutes: [String: Int]

    @Field(key: "blocked_dates")
    var blockedDates: [String]

    @Field(key: "recurring_commitments")
    var recurringCommitments: [StudyRecurringCommitment]

    @Field(key: "calendar_conflicts")
    var calendarConflicts: [StudyCalendarConflict]

    @Field(key: "estimate_presets")
    var estimatePresets: [StudyEstimatePreset]

    @Field(key: "time_zone_confirmed")
    var timeZoneConfirmed: Bool

    @Field(key: "availability_configured")
    var availabilityConfigured: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        weekdayCapacityMinutes: [String: Int] = StudySettings.defaultWeekdayCapacityMinutes,
        blockedDates: [String] = [],
        recurringCommitments: [StudyRecurringCommitment] = [],
        calendarConflicts: [StudyCalendarConflict] = [],
        estimatePresets: [StudyEstimatePreset] = StudyEstimatePreset.defaults,
        timeZoneConfirmed: Bool = false,
        availabilityConfigured: Bool = false
    ) {
        self.id = id
        self.$user.id = userID
        self.weekdayCapacityMinutes = weekdayCapacityMinutes
        self.blockedDates = blockedDates
        self.recurringCommitments = recurringCommitments
        self.calendarConflicts = calendarConflicts
        self.estimatePresets = estimatePresets
        self.timeZoneConfirmed = timeZoneConfirmed
        self.availabilityConfigured = availabilityConfigured
    }
}

struct StudySettingsRequest: Content {
    let weekdayCapacityMinutes: [String: Int]
    let blockedDates: [String]
    let recurringCommitments: [StudyRecurringCommitment]
    let calendarConflicts: [StudyCalendarConflict]
    let estimatePresets: [StudyEstimatePreset]
    let timeZoneConfirmed: Bool
    let availabilityConfigured: Bool
}

struct StudySettingsResponse: Content, Encodable {
    let weekdayCapacityMinutes: [String: Int]
    let blockedDates: [String]
    let recurringCommitments: [StudyRecurringCommitment]
    let calendarConflicts: [StudyCalendarConflict]
    let estimatePresets: [StudyEstimatePreset]
    let timeZoneConfirmed: Bool
    let availabilityConfigured: Bool

    init(settings: StudySettings?) {
        self.weekdayCapacityMinutes = settings?.weekdayCapacityMinutes
            ?? StudySettings.defaultWeekdayCapacityMinutes
        self.blockedDates = settings?.blockedDates ?? []
        self.recurringCommitments = settings?.recurringCommitments ?? []
        self.calendarConflicts = settings?.calendarConflicts ?? []
        self.estimatePresets = settings?.estimatePresets ?? StudyEstimatePreset.defaults
        self.timeZoneConfirmed = settings?.timeZoneConfirmed ?? false
        self.availabilityConfigured = settings?.availabilityConfigured ?? false
    }
}

struct BulkTaskEstimate: Content, Sendable {
    let taskID: UUID
    let estimatedMinutes: Int
}

struct BulkTaskEstimatesRequest: Content {
    let estimates: [BulkTaskEstimate]
    let estimatePresets: [StudyEstimatePreset]?
}

struct BulkTaskEstimatesResponse: Content {
    let updatedTaskCount: Int
    let estimatePresets: [StudyEstimatePreset]
}
