import Foundation
import Vapor

enum OAuthTokenAuthMethod: String, Sendable {
    case clientSecretBasic = "client_secret_basic"
    case clientSecretPost = "client_secret_post"
}

/// Holds the single generic OAuth provider configured for this deployment.
///
/// `providerID` is stored with account links, so it must stay stable after users
/// sign in. The display name can change without affecting persisted identities.
struct OAuthConfiguration: Sendable {
    let providerID: String
    let providerName: String
    let clientID: String
    let clientSecret: String
    let authorizationURL: String
    let tokenURL: String
    let userInfoURL: String
    let redirectURL: String
    let scopes: [String]
    let tokenAuthMethod: OAuthTokenAuthMethod
    let userIDField: String
    let emailField: String
    let nameField: String
    let emailVerifiedField: String
    let requiresVerifiedEmail: Bool

    init(
        providerID: String = "generic",
        providerName: String = "OAuth",
        clientID: String,
        clientSecret: String,
        authorizationURL: String,
        tokenURL: String,
        userInfoURL: String,
        redirectURL: String,
        scopes: [String] = ["openid", "profile", "email"],
        tokenAuthMethod: OAuthTokenAuthMethod = .clientSecretPost,
        userIDField: String = "sub",
        emailField: String = "email",
        nameField: String = "name",
        emailVerifiedField: String = "email_verified",
        requiresVerifiedEmail: Bool = true
    ) throws {
        self.providerID = try Self.requireValue(providerID, name: "OAUTH_PROVIDER_ID")
        self.providerName = try Self.requireValue(providerName, name: "OAUTH_PROVIDER_NAME")
        self.clientID = try Self.requireValue(clientID, name: "OAUTH_CLIENT_ID")
        self.clientSecret = try Self.requireValue(clientSecret, name: "OAUTH_CLIENT_SECRET")
        self.authorizationURL = try Self.requireHTTPURL(
            authorizationURL,
            name: "OAUTH_AUTHORIZATION_URL"
        )
        self.tokenURL = try Self.requireHTTPURL(tokenURL, name: "OAUTH_TOKEN_URL")
        self.userInfoURL = try Self.requireHTTPURL(userInfoURL, name: "OAUTH_USERINFO_URL")
        self.redirectURL = try Self.requireHTTPURL(redirectURL, name: "OAUTH_REDIRECT_URL")
        self.scopes = scopes
        self.tokenAuthMethod = tokenAuthMethod
        self.userIDField = try Self.requireValue(userIDField, name: "OAUTH_USER_ID_FIELD")
        self.emailField = try Self.requireValue(emailField, name: "OAUTH_EMAIL_FIELD")
        self.nameField = try Self.requireValue(nameField, name: "OAUTH_NAME_FIELD")
        self.emailVerifiedField = try Self.requireValue(
            emailVerifiedField,
            name: "OAUTH_EMAIL_VERIFIED_FIELD"
        )
        self.requiresVerifiedEmail = requiresVerifiedEmail
    }

    /// Returns no configuration when OAuth is absent, and rejects partial
    /// configuration at startup so the login page never offers a broken flow.
    static func fromEnvironment() throws -> OAuthConfiguration? {
        let requiredNames = [
            "OAUTH_CLIENT_ID",
            "OAUTH_CLIENT_SECRET",
            "OAUTH_AUTHORIZATION_URL",
            "OAUTH_TOKEN_URL",
            "OAUTH_USERINFO_URL",
            "OAUTH_REDIRECT_URL",
        ]
        let optionalNames = [
            "OAUTH_PROVIDER_ID",
            "OAUTH_PROVIDER_NAME",
            "OAUTH_SCOPES",
            "OAUTH_TOKEN_AUTH_METHOD",
            "OAUTH_USER_ID_FIELD",
            "OAUTH_EMAIL_FIELD",
            "OAUTH_NAME_FIELD",
            "OAUTH_EMAIL_VERIFIED_FIELD",
            "OAUTH_REQUIRE_VERIFIED_EMAIL",
        ]
        let values = Dictionary(
            uniqueKeysWithValues: (requiredNames + optionalNames).compactMap { name in
                Environment.get(name).map { (name, $0) }
            }
        )
        guard !values.isEmpty else {
            return nil
        }

        let missing = requiredNames.filter {
            values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        guard missing.isEmpty else {
            throw Abort(
                .internalServerError,
                reason: "OAuth configuration is incomplete. Set \(missing.joined(separator: ", "))."
            )
        }

        let tokenAuthMethodValue = values["OAUTH_TOKEN_AUTH_METHOD"]
        let tokenAuthMethod = try tokenAuthMethodValue.map {
            guard let method = OAuthTokenAuthMethod(rawValue: $0) else {
                throw Abort(
                    .internalServerError,
                    reason: "OAUTH_TOKEN_AUTH_METHOD must be client_secret_post or client_secret_basic."
                )
            }
            return method
        } ?? .clientSecretPost

        let verifiedEmailValue = values["OAUTH_REQUIRE_VERIFIED_EMAIL"]
        let requiresVerifiedEmail = try verifiedEmailValue.map {
            switch $0.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                throw Abort(
                    .internalServerError,
                    reason: "OAUTH_REQUIRE_VERIFIED_EMAIL must be true or false."
                )
            }
        } ?? true

        let scopes = values["OAUTH_SCOPES"]
            .map(Self.parseScopes)
            ?? ["openid", "profile", "email"]

        return try OAuthConfiguration(
            providerID: values["OAUTH_PROVIDER_ID"] ?? "generic",
            providerName: values["OAUTH_PROVIDER_NAME"] ?? "OAuth",
            clientID: values["OAUTH_CLIENT_ID"]!,
            clientSecret: values["OAUTH_CLIENT_SECRET"]!,
            authorizationURL: values["OAUTH_AUTHORIZATION_URL"]!,
            tokenURL: values["OAUTH_TOKEN_URL"]!,
            userInfoURL: values["OAUTH_USERINFO_URL"]!,
            redirectURL: values["OAUTH_REDIRECT_URL"]!,
            scopes: scopes,
            tokenAuthMethod: tokenAuthMethod,
            userIDField: values["OAUTH_USER_ID_FIELD"] ?? "sub",
            emailField: values["OAUTH_EMAIL_FIELD"] ?? "email",
            nameField: values["OAUTH_NAME_FIELD"] ?? "name",
            emailVerifiedField: values["OAUTH_EMAIL_VERIFIED_FIELD"] ?? "email_verified",
            requiresVerifiedEmail: requiresVerifiedEmail
        )
    }

    private static func parseScopes(_ value: String) -> [String] {
        value.split { $0 == "," || $0.isWhitespace }.map(String.init)
    }

    private static func requireValue(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.internalServerError, reason: "\(name) cannot be empty.")
        }
        return trimmed
    }

    private static func requireHTTPURL(_ value: String, name: String) throws -> String {
        let trimmed = try requireValue(value, name: name)
        guard
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host != nil
        else {
            throw Abort(.internalServerError, reason: "\(name) must be an absolute HTTP URL.")
        }
        return trimmed
    }
}

private struct OAuthConfigurationKey: StorageKey {
    typealias Value = OAuthConfiguration
}

extension Application {
    var oauthConfiguration: OAuthConfiguration? {
        get { storage[OAuthConfigurationKey.self] }
        set { storage[OAuthConfigurationKey.self] = newValue }
    }
}
