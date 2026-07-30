import Foundation
import Vapor

struct OAuthProfile: Sendable {
    let providerUserID: String
    let email: String?
    let name: String?
    let emailVerified: Bool?
}

enum OAuthService {
    /// Builds a transaction-specific authorization URL. State binds the callback
    /// to the browser session, and PKCE binds the authorization code to this request.
    static func authorizationURL(
        configuration: OAuthConfiguration,
        state: String,
        codeChallenge: String
    ) throws -> String {
        guard var components = URLComponents(string: configuration.authorizationURL) else {
            throw Abort(.internalServerError, reason: "The OAuth authorization URL is invalid.")
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURL),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ])
        components.queryItems = queryItems
        guard let url = components.url?.absoluteString else {
            throw Abort(.internalServerError, reason: "The OAuth authorization URL is invalid.")
        }
        return url
    }

    /// Exchanges the one-time code, then loads the stable provider subject and
    /// profile fields. Tokens remain in memory and are never stored or logged.
    static func profile(
        code: String,
        codeVerifier: String,
        configuration: OAuthConfiguration,
        client: any Client
    ) async throws -> OAuthProfile {
        let tokenResponse = try await client.post(
            URI(string: configuration.tokenURL),
            headers: ["Accept": "application/json"]
        ) { request in
            let clientID: String?
            let clientSecret: String?
            switch configuration.tokenAuthMethod {
            case .clientSecretBasic:
                request.headers.basicAuthorization = .init(
                    username: configuration.clientID,
                    password: configuration.clientSecret
                )
                clientID = nil
                clientSecret = nil
            case .clientSecretPost:
                clientID = configuration.clientID
                clientSecret = configuration.clientSecret
            }
            try request.content.encode(
                OAuthTokenRequest(
                    code: code,
                    redirectURI: configuration.redirectURL,
                    codeVerifier: codeVerifier,
                    clientID: clientID,
                    clientSecret: clientSecret
                ),
                as: .urlEncodedForm
            )
        }
        guard tokenResponse.status.code >= 200, tokenResponse.status.code < 300 else {
            throw Abort(.badGateway, reason: "The OAuth provider rejected the authorization code.")
        }

        let token: OAuthTokenResponse
        do {
            token = try tokenResponse.content.decode(OAuthTokenResponse.self)
        } catch {
            throw Abort(.badGateway, reason: "The OAuth provider returned an invalid token response.")
        }
        guard !token.accessToken.isEmpty else {
            throw Abort(.badGateway, reason: "The OAuth provider did not return an access token.")
        }
        if let tokenType = token.tokenType, tokenType.lowercased() != "bearer" {
            throw Abort(.badGateway, reason: "The OAuth provider returned an unsupported token type.")
        }

        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: token.accessToken)
        headers.add(name: .accept, value: "application/json")
        let userInfoResponse = try await client.get(
            URI(string: configuration.userInfoURL),
            headers: headers
        )
        guard userInfoResponse.status.code >= 200, userInfoResponse.status.code < 300 else {
            throw Abort(.badGateway, reason: "The OAuth provider rejected the profile request.")
        }
        guard let body = userInfoResponse.body else {
            throw Abort(.badGateway, reason: "The OAuth provider returned an empty profile.")
        }

        return try decodeProfile(
            Data(body.readableBytesView),
            configuration: configuration
        )
    }

    static func randomURLSafeValue(byteCount: Int = 32) -> String {
        Data([UInt8].random(count: byteCount)).base64URLString
    }

    static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
    }

    /// Reads configured field paths and accepts either `sub` or `id` as a
    /// fallback. Numeric provider IDs are normalized to strings for storage.
    private static func decodeProfile(
        _ data: Data,
        configuration: OAuthConfiguration
    ) throws -> OAuthProfile {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Abort(.badGateway, reason: "The OAuth provider returned an invalid profile.")
        }
        guard let values = object as? [String: Any] else {
            throw Abort(.badGateway, reason: "The OAuth provider returned an invalid profile.")
        }

        let identifierFields = [configuration.userIDField, "sub", "id"]
        let providerUserID = identifierFields.lazy
            .compactMap { scalarString(value(at: $0, in: values)) }
            .first
        guard let providerUserID, !providerUserID.isEmpty else {
            throw Abort(.badGateway, reason: "The OAuth profile has no stable user identifier.")
        }

        return OAuthProfile(
            providerUserID: providerUserID,
            email: string(value(at: configuration.emailField, in: values)),
            name: string(value(at: configuration.nameField, in: values)),
            emailVerified: boolean(value(at: configuration.emailVerifiedField, in: values))
        )
    }

    private static func value(at path: String, in values: [String: Any]) -> Any? {
        var current: Any = values
        for component in path.split(separator: ".").map(String.init) {
            guard let object = current as? [String: Any], let next = object[component] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scalarString(_ value: Any?) -> String? {
        if let value = string(value) {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

private struct OAuthTokenRequest: Content {
    let grantType = "authorization_code"
    let code: String
    let redirectURI: String
    let codeVerifier: String
    let clientID: String?
    let clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case redirectURI = "redirect_uri"
        case codeVerifier = "code_verifier"
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

private struct OAuthTokenResponse: Content {
    let accessToken: String
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
