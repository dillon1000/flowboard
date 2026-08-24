import Fluent
import Foundation
import Vapor

enum MCPOAuthService {
    static let scope = "flowboard:read"
    static let accessTokenLifetime: TimeInterval = 60 * 60
    static let refreshTokenLifetime: TimeInterval = 60 * 60 * 24 * 30

    static func publicOrigin(for req: Request) throws -> String {
        let scheme = req.headers.first(name: "x-forwarded-proto") ?? req.url.scheme ?? "http"
        let host = req.headers.first(name: "x-forwarded-host") ?? req.headers.first(name: .host)
        guard let host, !host.isEmpty, ["http", "https"].contains(scheme.lowercased()) else {
            throw Abort(.internalServerError, reason: "The public application origin is unavailable.")
        }
        return "\(scheme.lowercased())://\(host)"
    }

    static func resourceURL(for req: Request) throws -> String {
        "\(try publicOrigin(for: req))/mcp"
    }

    static func validateRedirectURI(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), components.fragment == nil else {
            return false
        }
        if components.scheme?.lowercased() == "https" {
            return components.host?.isEmpty == false
        }
        guard components.scheme?.lowercased() == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(components.host?.lowercased() ?? "")
    }

    static func createClient(
        input: MCPOAuthClientRegistrationRequest,
        on database: any Database
    ) async throws -> MCPOAuthClient {
        guard input.tokenEndpointAuthMethod == nil || input.tokenEndpointAuthMethod == "none" else {
            throw Abort(.badRequest, reason: "Only public OAuth clients are supported.")
        }
        guard input.grantTypes?.allSatisfy({ ["authorization_code", "refresh_token"].contains($0) }) != false,
              input.responseTypes?.allSatisfy({ $0 == "code" }) != false else {
            throw Abort(.badRequest, reason: "Only authorization-code clients are supported.")
        }
        let redirectURIs = Array(Set(input.redirectURIs))
        guard !redirectURIs.isEmpty, redirectURIs.count <= 10,
              redirectURIs.allSatisfy(validateRedirectURI) else {
            throw Abort(.badRequest, reason: "Register 1 to 10 HTTPS or loopback redirect URIs.")
        }
        let name = input.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "MCP client"
        guard (1...120).contains(name.count) else {
            throw Abort(.badRequest, reason: "Client names must contain 1 to 120 characters.")
        }
        let client = MCPOAuthClient(
            clientID: "mcp_\(OAuthService.randomURLSafeValue(byteCount: 24))",
            clientName: name,
            redirectURIs: redirectURIs
        )
        try await client.create(on: database)
        return client
    }

    static func validatedAuthorization(
        _ input: MCPOAuthAuthorizationQuery,
        resourceURL: String,
        on database: any Database
    ) async throws -> MCPOAuthClient {
        guard input.responseType == "code",
              input.codeChallengeMethod == "S256",
              (43...128).contains(input.codeChallenge.count) else {
            throw Abort(.badRequest, reason: "Use the authorization-code flow with S256 PKCE.")
        }
        guard input.resource == nil || input.resource == resourceURL else {
            throw Abort(.badRequest, reason: "The OAuth resource does not identify this MCP server.")
        }
        let requestedScopes = Set((input.scope ?? scope).split(separator: " ").map(String.init))
        guard !requestedScopes.isEmpty, requestedScopes.isSubset(of: [scope]) else {
            throw Abort(.badRequest, reason: "The requested OAuth scope is not supported.")
        }
        guard let client = try await MCPOAuthClient.query(on: database)
            .filter(\.$clientID == input.clientID)
            .first(),
              client.redirectURIs.contains(input.redirectURI) else {
            throw Abort(.badRequest, reason: "The OAuth client or redirect URI is invalid.")
        }
        return client
    }

    static func issueAuthorizationCode(
        input: MCPOAuthAuthorizationDecision,
        userID: UUID,
        client: MCPOAuthClient,
        on database: any Database
    ) async throws -> String {
        let rawCode = OAuthService.randomURLSafeValue()
        let code = MCPOAuthAuthorizationCode(
            userID: userID,
            clientID: try client.requireID(),
            codeHash: APIKeyService.hash(rawCode),
            redirectURI: input.redirectURI,
            codeChallenge: input.codeChallenge,
            scope: scope,
            expiresAt: Date(timeIntervalSinceNow: 5 * 60)
        )
        try await code.create(on: database)
        return rawCode
    }

    static func exchange(
        input: MCPOAuthTokenRequest,
        resourceURL: String,
        on database: any Database
    ) async throws -> MCPOAuthTokenResponse {
        guard input.resource == nil || input.resource == resourceURL else {
            throw OAuthExchangeError.invalidGrant
        }
        switch input.grantType {
        case "authorization_code":
            return try await exchangeAuthorizationCode(input: input, on: database)
        case "refresh_token":
            return try await exchangeRefreshToken(input: input, on: database)
        default:
            throw OAuthExchangeError.unsupportedGrantType
        }
    }

    static func authenticate(_ rawToken: String, on database: any Database) async throws -> User? {
        guard let token = try await MCPOAuthToken.query(on: database)
            .filter(\.$accessTokenHash == APIKeyService.hash(rawToken))
            .with(\.$user)
            .first(), token.accessTokenExpiresAt > Date() else {
            return nil
        }
        return token.user
    }

    private static func exchangeAuthorizationCode(
        input: MCPOAuthTokenRequest,
        on database: any Database
    ) async throws -> MCPOAuthTokenResponse {
        guard let rawCode = input.code,
              let redirectURI = input.redirectURI,
              let verifier = input.codeVerifier,
              (43...128).contains(verifier.count),
              let client = try await MCPOAuthClient.query(on: database)
                .filter(\.$clientID == input.clientID)
                .first(),
              let code = try await MCPOAuthAuthorizationCode.query(on: database)
                .filter(\.$codeHash == APIKeyService.hash(rawCode))
                .first() else {
            throw OAuthExchangeError.invalidGrant
        }
        try await code.delete(on: database)
        guard code.expiresAt > Date(), code.$client.id == client.id,
              code.redirectURI == redirectURI,
              OAuthService.codeChallenge(for: verifier) == code.codeChallenge else {
            throw OAuthExchangeError.invalidGrant
        }
        return try await issueTokens(
            userID: code.$user.id,
            clientID: try client.requireID(),
            scope: code.scope,
            replacing: nil,
            on: database
        )
    }

    private static func exchangeRefreshToken(
        input: MCPOAuthTokenRequest,
        on database: any Database
    ) async throws -> MCPOAuthTokenResponse {
        guard let rawRefreshToken = input.refreshToken,
              let client = try await MCPOAuthClient.query(on: database)
                .filter(\.$clientID == input.clientID)
                .first(),
              let token = try await MCPOAuthToken.query(on: database)
                .filter(\.$refreshTokenHash == APIKeyService.hash(rawRefreshToken))
                .first(), token.refreshTokenExpiresAt > Date(), token.$client.id == client.id else {
            throw OAuthExchangeError.invalidGrant
        }
        return try await issueTokens(
            userID: token.$user.id,
            clientID: try client.requireID(),
            scope: token.scope,
            replacing: token,
            on: database
        )
    }

    private static func issueTokens(
        userID: UUID,
        clientID: UUID,
        scope: String,
        replacing token: MCPOAuthToken?,
        on database: any Database
    ) async throws -> MCPOAuthTokenResponse {
        let accessToken = "mcp_at_\(OAuthService.randomURLSafeValue())"
        let refreshToken = "mcp_rt_\(OAuthService.randomURLSafeValue())"
        let now = Date()
        let record = token ?? MCPOAuthToken(
            userID: userID,
            clientID: clientID,
            accessTokenHash: "",
            refreshTokenHash: "",
            scope: scope,
            accessTokenExpiresAt: now,
            refreshTokenExpiresAt: now
        )
        record.accessTokenHash = APIKeyService.hash(accessToken)
        record.refreshTokenHash = APIKeyService.hash(refreshToken)
        record.accessTokenExpiresAt = now.addingTimeInterval(accessTokenLifetime)
        record.refreshTokenExpiresAt = now.addingTimeInterval(refreshTokenLifetime)
        if token == nil {
            try await record.create(on: database)
        } else {
            try await record.update(on: database)
        }
        return MCPOAuthTokenResponse(
            accessToken: accessToken,
            expiresIn: Int(accessTokenLifetime),
            refreshToken: refreshToken,
            scope: scope
        )
    }
}

enum OAuthExchangeError: Error {
    case invalidGrant
    case unsupportedGrantType
}
