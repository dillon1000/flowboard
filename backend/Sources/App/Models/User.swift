import Fluent
import Vapor

final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @OptionalField(key: "profile_picture_url")
    var profilePictureURL: String?

    @Field(key: "time_zone")
    var timeZoneIdentifier: String

    @Field(key: "daily_brief_enabled")
    var dailyBriefEnabled: Bool

    @Field(key: "weekly_planning_prompt_enabled")
    var weeklyPlanningPromptEnabled: Bool

    /// The local 0...23 hour comes from profile settings. Seven sends at 7 AM.
    @Field(key: "planning_email_hour")
    var planningEmailHour: Int

    @Children(for: \.$owner)
    var boards: [Board]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        email: String,
        passwordHash: String,
        profilePictureURL: String? = nil,
        timeZoneIdentifier: String = "UTC",
        dailyBriefEnabled: Bool = false,
        weeklyPlanningPromptEnabled: Bool = false,
        planningEmailHour: Int = 7
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.passwordHash = passwordHash
        self.profilePictureURL = profilePictureURL
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dailyBriefEnabled = dailyBriefEnabled
        self.weeklyPlanningPromptEnabled = weeklyPlanningPromptEnabled
        self.planningEmailHour = planningEmailHour
    }
}

extension User: ModelCredentialsAuthenticatable {
    static var usernameKey: KeyPath<User, Field<String>> { \.$email }
    static var passwordHashKey: KeyPath<User, Field<String>> { \.$passwordHash }

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: passwordHash)
    }
}

extension User: ModelSessionAuthenticatable {}

struct UserResponse: Content {
    let id: UUID
    let name: String
    let email: String
    let profilePictureURL: String?
    let timeZone: String
    let dailyBriefEnabled: Bool
    let weeklyPlanningPromptEnabled: Bool
    let planningEmailHour: Int
    let createdAt: Date?

    init(user: User) throws {
        self.id = try user.requireID()
        self.name = user.name
        self.email = user.email
        self.profilePictureURL = user.profilePictureURL
        self.timeZone = user.timeZoneIdentifier
        self.dailyBriefEnabled = user.dailyBriefEnabled
        self.weeklyPlanningPromptEnabled = user.weeklyPlanningPromptEnabled
        self.planningEmailHour = user.planningEmailHour
        self.createdAt = user.createdAt
    }
}

struct RegisterRequest: Content, Validatable {
    let name: String
    let email: String
    let password: String
    let timeZone: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...72))
    }
}

struct LoginRequest: Content, Validatable {
    let email: String
    let password: String
    let timeZone: String?

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(1...72))
    }
}

struct UpdateProfileRequest: Content, Validatable {
    let name: String
    let timeZone: String?
    let dailyBriefEnabled: Bool?
    let weeklyPlanningPromptEnabled: Bool?
    let planningEmailHour: Int?

    init(
        name: String,
        timeZone: String? = nil,
        dailyBriefEnabled: Bool? = nil,
        weeklyPlanningPromptEnabled: Bool? = nil,
        planningEmailHour: Int? = nil
    ) {
        self.name = name
        self.timeZone = timeZone
        self.dailyBriefEnabled = dailyBriefEnabled
        self.weeklyPlanningPromptEnabled = weeklyPlanningPromptEnabled
        self.planningEmailHour = planningEmailHour
    }

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
    }
}

/// Accepts named IANA zones plus UTC. The strict list avoids storing fixed-offset
/// aliases that do not follow local daylight-saving transitions.
func validatedTimeZoneIdentifier(_ suppliedValue: String?) throws -> String? {
    guard let suppliedValue else { return nil }
    let value = suppliedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(value) else {
        throw Abort(.unprocessableEntity, reason: "Choose a valid IANA time zone.")
    }
    return value
}
