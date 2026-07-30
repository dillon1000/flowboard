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

    @Children(for: \.$owner)
    var boards: [Board]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, email: String, passwordHash: String) {
        self.id = id
        self.name = name
        self.email = email
        self.passwordHash = passwordHash
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
    let createdAt: Date?

    init(user: User) throws {
        self.id = try user.requireID()
        self.name = user.name
        self.email = user.email
        self.createdAt = user.createdAt
    }
}

struct RegisterRequest: Content, Validatable {
    let name: String
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...72))
    }
}

struct LoginRequest: Content, Validatable {
    let email: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(1...72))
    }
}

struct UpdateProfileRequest: Content, Validatable {
    let name: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
    }
}
