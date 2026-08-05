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

        return try await createUserWithWorkspace(
            name: name,
            email: email,
            passwordHash: Bcrypt.hash(input.password),
            profilePictureURL: nil,
            timeZoneIdentifier: try validatedTimeZoneIdentifier(input.timeZone) ?? "UTC",
            oauthIdentity: nil,
            on: database
        )
    }

    static func authenticate(_ input: LoginRequest, on database: any Database) async throws -> User {
        let email = input.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard
            let user = try await User.query(on: database).filter(\.$email == email).first(),
            try user.verify(password: input.password)
        else {
            throw Abort(.unauthorized, reason: "The email or password is incorrect.")
        }
        if let timeZoneIdentifier = try validatedTimeZoneIdentifier(input.timeZone),
           user.timeZoneIdentifier != timeZoneIdentifier {
            user.timeZoneIdentifier = timeZoneIdentifier
            try await user.update(on: database)
        }
        return user
    }

    /// Resolves a stable provider subject to an existing account or creates a
    /// user and first workspace. New email links require provider verification
    /// unless the deployment explicitly trusts its provider without that claim.
    static func authenticateOAuth(
        _ profile: OAuthProfile,
        providerID: String,
        requiresVerifiedEmail: Bool,
        on database: any Database
    ) async throws -> User {
        if let account = try await OAuthAccount.query(on: database)
            .filter(\.$providerID == providerID)
            .filter(\.$providerUserID == profile.providerUserID)
            .with(\.$user)
            .first()
        {
            try await syncOAuthProfilePicture(
                normalizedProfilePictureURL(profile.pictureURL),
                for: account.user,
                on: database
            )
            return account.user
        }

        guard let suppliedEmail = profile.email else {
            throw Abort(.unprocessableEntity, reason: "The OAuth provider did not supply an email.")
        }
        if requiresVerifiedEmail, profile.emailVerified != true {
            throw Abort(
                .unprocessableEntity,
                reason: "The OAuth provider did not verify the account email."
            )
        }

        let email = suppliedEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !Validator<String>.email.validate(email).isFailure else {
            throw Abort(.unprocessableEntity, reason: "The OAuth provider supplied an invalid email.")
        }
        let profilePictureURL = normalizedProfilePictureURL(profile.pictureURL)
        if let user = try await User.query(on: database).filter(\.$email == email).first() {
            try await database.transaction { transaction in
                try await syncOAuthProfilePicture(
                    profilePictureURL,
                    for: user,
                    on: transaction
                )
                try await OAuthAccount(
                    userID: try user.requireID(),
                    providerID: providerID,
                    providerUserID: profile.providerUserID
                ).create(on: transaction)
            }
            return user
        }

        let name = oauthDisplayName(profile.name, email: email)
        return try await createUserWithWorkspace(
            name: name,
            email: email,
            passwordHash: Bcrypt.hash(OAuthService.randomURLSafeValue(byteCount: 48)),
            profilePictureURL: profilePictureURL,
            timeZoneIdentifier: "UTC",
            oauthIdentity: (providerID, profile.providerUserID),
            on: database
        )
    }

    /// Creates all records needed for a usable account in one transaction.
    /// OAuth identity creation is optional because password registration uses
    /// the same workspace bootstrap without a provider link.
    private static func createUserWithWorkspace(
        name: String,
        email: String,
        passwordHash: String,
        profilePictureURL: String?,
        timeZoneIdentifier: String,
        oauthIdentity: (providerID: String, providerUserID: String)?,
        on database: any Database
    ) async throws -> User {
        let userID = UUID()
        let user = User(
            id: userID,
            name: name,
            email: email,
            passwordHash: passwordHash,
            profilePictureURL: profilePictureURL,
            timeZoneIdentifier: timeZoneIdentifier
        )

        return try await database.transaction { transaction in
            try await user.create(on: transaction)
            if let oauthIdentity {
                try await OAuthAccount(
                    userID: userID,
                    providerID: oauthIdentity.providerID,
                    providerUserID: oauthIdentity.providerUserID
                ).create(on: transaction)
            }
            _ = try await WorkspaceService.createBoard(
                name: "My board",
                slug: "my-board-\(userID.uuidString.prefix(8).lowercased())",
                ownerID: userID,
                on: transaction
            )
            return user
        }
    }

    private static func oauthDisplayName(_ suppliedName: String?, email: String) -> String {
        let name = suppliedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.count >= 2 {
            return String(name.prefix(80))
        }
        let emailName = String(email.split(separator: "@", maxSplits: 1).first ?? "")
        return emailName.count >= 2 ? String(emailName.prefix(80)) : "OAuth user"
    }

    /// Accepts only bounded HTTPS URLs because the value is rendered as an image
    /// source on authenticated pages. Invalid or missing claims remove stale images.
    private static func normalizedProfilePictureURL(_ suppliedURL: String?) -> String? {
        guard
            let suppliedURL,
            suppliedURL.count <= 2_048,
            let components = URLComponents(string: suppliedURL),
            components.scheme?.lowercased() == "https",
            components.host != nil
        else {
            return nil
        }
        return suppliedURL
    }

    /// Synchronizes the provider-managed image on every OAuth login. The update
    /// is skipped when the stored value already matches, which avoids timestamp churn.
    private static func syncOAuthProfilePicture(
        _ profilePictureURL: String?,
        for user: User,
        on database: any Database
    ) async throws {
        guard user.profilePictureURL != profilePictureURL else {
            return
        }
        user.profilePictureURL = profilePictureURL
        try await user.update(on: database)
    }
}
