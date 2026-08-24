import Fluent
import Foundation
import Vapor

final class MCPOAuthClient: Model, @unchecked Sendable {
    static let schema = "mcp_oauth_clients"

    @ID(key: .id) var id: UUID?
    @Field(key: "client_id") var clientID: String
    @Field(key: "client_name") var clientName: String
    @Field(key: "redirect_uris") var redirectURIs: [String]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, clientID: String, clientName: String, redirectURIs: [String]) {
        self.id = id
        self.clientID = clientID
        self.clientName = clientName
        self.redirectURIs = redirectURIs
    }
}

final class MCPOAuthAuthorizationCode: Model, @unchecked Sendable {
    static let schema = "mcp_oauth_authorization_codes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Parent(key: "client_id") var client: MCPOAuthClient
    @Field(key: "code_hash") var codeHash: String
    @Field(key: "redirect_uri") var redirectURI: String
    @Field(key: "code_challenge") var codeChallenge: String
    @Field(key: "scope") var scope: String
    @Field(key: "expires_at") var expiresAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        clientID: UUID,
        codeHash: String,
        redirectURI: String,
        codeChallenge: String,
        scope: String,
        expiresAt: Date
    ) {
        self.id = id
        self.$user.id = userID
        self.$client.id = clientID
        self.codeHash = codeHash
        self.redirectURI = redirectURI
        self.codeChallenge = codeChallenge
        self.scope = scope
        self.expiresAt = expiresAt
    }
}

final class MCPOAuthToken: Model, @unchecked Sendable {
    static let schema = "mcp_oauth_tokens"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Parent(key: "client_id") var client: MCPOAuthClient
    @Field(key: "access_token_hash") var accessTokenHash: String
    @Field(key: "refresh_token_hash") var refreshTokenHash: String
    @Field(key: "scope") var scope: String
    @Field(key: "access_token_expires_at") var accessTokenExpiresAt: Date
    @Field(key: "refresh_token_expires_at") var refreshTokenExpiresAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        clientID: UUID,
        accessTokenHash: String,
        refreshTokenHash: String,
        scope: String,
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date
    ) {
        self.id = id
        self.$user.id = userID
        self.$client.id = clientID
        self.accessTokenHash = accessTokenHash
        self.refreshTokenHash = refreshTokenHash
        self.scope = scope
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

struct MCPOAuthClientRegistrationRequest: Content {
    let clientName: String?
    let redirectURIs: [String]
    let tokenEndpointAuthMethod: String?
    let grantTypes: [String]?
    let responseTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case clientName = "client_name"
        case redirectURIs = "redirect_uris"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
    }
}

struct MCPOAuthClientRegistrationResponse: Content {
    let clientID: String
    let clientName: String
    let redirectURIs: [String]
    let tokenEndpointAuthMethod = "none"
    let grantTypes = ["authorization_code", "refresh_token"]
    let responseTypes = ["code"]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientName = "client_name"
        case redirectURIs = "redirect_uris"
        case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        case grantTypes = "grant_types"
        case responseTypes = "response_types"
    }
}

struct MCPOAuthAuthorizationQuery: Content {
    let responseType: String
    let clientID: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let state: String?
    let scope: String?
    let resource: String?

    enum CodingKeys: String, CodingKey {
        case responseType = "response_type"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
        case state, scope, resource
    }
}

struct MCPOAuthAuthorizationDecision: Content {
    let responseType: String
    let clientID: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let state: String?
    let scope: String?
    let resource: String?
    let decision: String

    enum CodingKeys: String, CodingKey {
        case responseType = "response_type"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
        case state, scope, resource, decision
    }
}

struct MCPOAuthTokenRequest: Content {
    let grantType: String
    let code: String?
    let redirectURI: String?
    let clientID: String
    let codeVerifier: String?
    let refreshToken: String?
    let resource: String?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case codeVerifier = "code_verifier"
        case refreshToken = "refresh_token"
        case code, resource
    }
}

struct MCPOAuthTokenResponse: Content {
    let accessToken: String
    let tokenType = "Bearer"
    let expiresIn: Int
    let refreshToken: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct MCPOAuthErrorResponse: Content {
    let error: String
    let errorDescription: String

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
