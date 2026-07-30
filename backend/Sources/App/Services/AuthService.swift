import Fluent
import Vapor

enum AuthService {
    /// Creates a user and their first persisted board in one transaction. A failure
    /// rolls back both records so an account can never exist without a workspace.
    static func register(_ input: RegisterRequest, on database: any Database) async throws -> User {
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard try await User.query(on: database).filter(\.$email == email).first() == nil else {
            throw Abort(.conflict, reason: "An account already uses this email.")
        }

        let userID = UUID()
        let user = try User(
            id: userID,
            name: name,
            email: email,
            passwordHash: Bcrypt.hash(input.password)
        )

        return try await database.transaction { transaction in
            try await user.create(on: transaction)

            _ = try await WorkspaceService.createBoard(
                name: "My board",
                slug: "my-board-\(userID.uuidString.prefix(8).lowercased())",
                ownerID: userID,
                on: transaction
            )

            return user
        }
    }

    static func authenticate(_ input: LoginRequest, on database: any Database) async throws -> User {
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard
            let user = try await User.query(on: database).filter(\.$email == email).first(),
            try user.verify(password: input.password)
        else {
            throw Abort(.unauthorized, reason: "The email or password is incorrect.")
        }
        return user
    }
}
