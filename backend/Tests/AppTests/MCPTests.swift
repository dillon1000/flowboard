@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("MCP OAuth server")
struct MCPTests {
    @Test("OAuth discovery, PKCE, and protected MCP initialize work together")
    func oauthFlow() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let hostHeaders = HTTPHeaders([("Host", "flowboard.example")])

            let metadata = try await app.testing().sendRequest(
                .GET,
                ".well-known/oauth-protected-resource/mcp",
                headers: hostHeaders
            )
            #expect(metadata.status == .ok)
            let metadataBody = metadata.body.getString(at: 0, length: metadata.body.readableBytes)
            #expect(metadataBody?.contains("http://flowboard.example/mcp") == true)

            let unauthorized = try await app.testing().sendRequest(
                .POST,
                "mcp",
                headers: hostHeaders,
                beforeRequest: { request in
                    try request.content.encode(initializeRequest())
                }
            )
            #expect(unauthorized.status == .unauthorized)
            #expect(unauthorized.headers.first(name: .wwwAuthenticate)?.contains("resource_metadata") == true)

            let client = try await registerClient(on: app, headers: hostHeaders)
            let verifier = String(repeating: "a", count: 64)
            let codeChallenge = OAuthService.codeChallenge(for: verifier)
            let resource = "http://flowboard.example/mcp"
            let authorizePath = try authorizationPath(
                clientID: client.clientID,
                redirectURI: client.redirectURIs[0],
                codeChallenge: codeChallenge,
                resource: resource
            )

            let consent = try await app.testing().sendRequest(
                .GET,
                authorizePath,
                headers: HTTPHeaders([
                    ("Host", "flowboard.example"),
                    ("Cookie", session.cookie),
                ])
            )
            #expect(consent.status == .ok)
            #expect(consent.body.getString(at: 0, length: consent.body.readableBytes)?.contains("Claude test") == true)

            let decision = try await app.testing().sendRequest(
                .POST,
                "oauth/authorize",
                headers: HTTPHeaders([
                    ("Host", "flowboard.example"),
                    ("Cookie", session.cookie),
                ]),
                beforeRequest: { request in
                    try request.content.encode(
                        MCPOAuthAuthorizationDecision(
                            responseType: "code",
                            clientID: client.clientID,
                            redirectURI: client.redirectURIs[0],
                            codeChallenge: codeChallenge,
                            codeChallengeMethod: "S256",
                            state: "test-state",
                            scope: MCPOAuthService.scope,
                            resource: resource,
                            decision: "allow"
                        ),
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(decision.status == .seeOther)
            let callback = try #require(decision.headers.first(name: .location))
            let callbackComponents = try #require(URLComponents(string: callback))
            let code = try #require(callbackComponents.queryItems?.first { $0.name == "code" }?.value)
            #expect(callbackComponents.queryItems?.first { $0.name == "state" }?.value == "test-state")

            let token = try await exchangeCode(
                code,
                verifier: verifier,
                client: client,
                resource: resource,
                on: app,
                headers: hostHeaders
            )
            #expect(token.tokenType == "Bearer")
            #expect(token.scope == MCPOAuthService.scope)

            var mcpHeaders = hostHeaders
            mcpHeaders.bearerAuthorization = .init(token: token.accessToken)
            let initialize = try await app.testing().sendRequest(
                .POST,
                "mcp",
                headers: mcpHeaders,
                beforeRequest: { request in
                    try request.content.encode(initializeRequest())
                }
            )
            #expect(initialize.status == .ok)
            let response = try initialize.content.decode(MCPResponse.self)
            #expect(response.error == nil)
            #expect(response.result?.objectValue?["serverInfo"]?.objectValue?["name"]?.stringValue == "flowboard")

            let storedClient = try #require(try await MCPOAuthClient.query(on: app.db)
                .filter(\.$clientID == client.clientID)
                .first())
            let manager = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/settings/connected-apps",
                headers: HTTPHeaders([("Cookie", session.cookie)])
            )
            #expect(manager.status == .ok)
            #expect(manager.body.getString(at: 0, length: manager.body.readableBytes)?.contains("Claude test") == true)

            let disconnected = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/oauth-connections/\(try storedClient.requireID())",
                headers: HTTPHeaders([("Cookie", session.cookie)])
            )
            #expect(disconnected.status == .noContent)
            let revoked = try await app.testing().sendRequest(
                .POST,
                "mcp",
                headers: mcpHeaders,
                beforeRequest: { request in try request.content.encode(initializeRequest()) }
            )
            #expect(revoked.status == .unauthorized)
        }
    }

    @Test("MCP tools include descriptions and linked Canvas academic data")
    func canvasData() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let board = try #require(try await Board.find(session.boardID, on: app.db))
            board.description = "Biology course work and lab planning."
            try await board.update(on: app.db)

            let task = Task(
                boardID: session.boardID,
                title: "Cell microscopy report",
                description: "Compare the observed cell structures and include labeled images.",
                position: 1_000,
                dueAt: Date(timeIntervalSince1970: 1_800_000_000),
                gradeEarned: 18,
                gradePossible: 20,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let connection = CanvasConnection(
                userID: session.userID,
                canvasOrigin: "https://canvas.example.edu",
                syncKeyHash: "secret-hash",
                syncKeyPrefix: "fcs_example"
            )
            try await connection.create(on: app.db)
            let course = CanvasCourseLink(
                connectionID: try connection.requireID(),
                remoteCourseID: "BIO-101",
                boardID: session.boardID,
                canvasCourseURL: "https://canvas.example.edu/courses/101",
                courseCode: "BIO 101",
                termName: "Fall 2026",
                currentScore: 91.5,
                currentGrade: "A-"
            )
            try await course.create(on: app.db)
            let assignment = CanvasAssignmentLink(
                courseLinkID: try course.requireID(),
                remoteAssignmentID: "assignment-501",
                taskID: try task.requireID(),
                canvasAssignmentURL: "https://canvas.example.edu/courses/101/assignments/501"
            )
            assignment.submissionState = "submitted"
            assignment.gradeLabel = "18 / 20"
            try await assignment.create(on: app.db)

            let hostHeaders = HTTPHeaders([("Host", "flowboard.example")])
            let token = try await authorize(session: session, on: app, headers: hostHeaders)
            var mcpHeaders = hostHeaders
            mcpHeaders.bearerAuthorization = .init(token: token.accessToken)
            let call = MCPRequest(
                jsonrpc: "2.0",
                id: .integer(2),
                method: "tools/call",
                params: .object([
                    "name": .string("get_canvas_data"),
                    "arguments": .object([:]),
                ])
            )
            let response = try await app.testing().sendRequest(
                .POST,
                "mcp",
                headers: mcpHeaders,
                beforeRequest: { request in try request.content.encode(call) }
            )
            #expect(response.status == .ok)
            let body = response.body.getString(at: 0, length: response.body.readableBytes) ?? ""
            #expect(body.contains("Cell microscopy report"))
            #expect(body.contains("Compare the observed cell structures"))
            #expect(body.contains("BIO 101"))
            #expect(body.contains("Fall 2026"))
            #expect(body.contains("submitted"))
            #expect(body.contains("18 / 20"))
            #expect(!body.contains("secret-hash"))
            #expect(!body.contains("fcs_example"))
        }
    }

    private func authorize(
        session: (cookie: String, boardID: UUID, userID: UUID),
        on app: Application,
        headers: HTTPHeaders
    ) async throws -> MCPOAuthTokenResponse {
        let client = try await registerClient(on: app, headers: headers)
        let verifier = String(repeating: "b", count: 64)
        let challenge = OAuthService.codeChallenge(for: verifier)
        let resource = "http://flowboard.example/mcp"
        var decisionHeaders = headers
        decisionHeaders.add(name: .cookie, value: session.cookie)
        let decision = try await app.testing().sendRequest(
            .POST,
            "oauth/authorize",
            headers: decisionHeaders,
            beforeRequest: { request in
                try request.content.encode(
                    MCPOAuthAuthorizationDecision(
                        responseType: "code",
                        clientID: client.clientID,
                        redirectURI: client.redirectURIs[0],
                        codeChallenge: challenge,
                        codeChallengeMethod: "S256",
                        state: nil,
                        scope: MCPOAuthService.scope,
                        resource: resource,
                        decision: "allow"
                    ),
                    as: .urlEncodedForm
                )
            }
        )
        let location = try #require(decision.headers.first(name: .location))
        let code = try #require(URLComponents(string: location)?.queryItems?.first { $0.name == "code" }?.value)
        return try await exchangeCode(
            code,
            verifier: verifier,
            client: client,
            resource: resource,
            on: app,
            headers: headers
        )
    }

    private func registerClient(
        on app: Application,
        headers: HTTPHeaders
    ) async throws -> MCPOAuthClientRegistrationResponse {
        let response = try await app.testing().sendRequest(
            .POST,
            "oauth/register",
            headers: headers,
            beforeRequest: { request in
                try request.content.encode(MCPOAuthClientRegistrationRequest(
                    clientName: "Claude test",
                    redirectURIs: ["http://127.0.0.1:7777/callback"],
                    tokenEndpointAuthMethod: "none",
                    grantTypes: ["authorization_code", "refresh_token"],
                    responseTypes: ["code"]
                ))
            }
        )
        #expect(response.status == .created)
        return try response.content.decode(MCPOAuthClientRegistrationResponse.self)
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        client: MCPOAuthClientRegistrationResponse,
        resource: String,
        on app: Application,
        headers: HTTPHeaders
    ) async throws -> MCPOAuthTokenResponse {
        let response = try await app.testing().sendRequest(
            .POST,
            "oauth/token",
            headers: headers,
            beforeRequest: { request in
                try request.content.encode(
                    MCPOAuthTokenRequest(
                        grantType: "authorization_code",
                        code: code,
                        redirectURI: client.redirectURIs[0],
                        clientID: client.clientID,
                        codeVerifier: verifier,
                        refreshToken: nil,
                        resource: resource
                    ),
                    as: .urlEncodedForm
                )
            }
        )
        #expect(response.status == .ok)
        let body = response.body.getString(at: 0, length: response.body.readableBytes) ?? ""
        #expect(body.contains("\"access_token\""))
        #expect(body.contains("\"token_type\":\"Bearer\""))
        return try response.content.decode(MCPOAuthTokenResponse.self)
    }

    private func authorizationPath(
        clientID: String,
        redirectURI: String,
        codeChallenge: String,
        resource: String
    ) throws -> String {
        var components = URLComponents()
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: "test-state"),
            URLQueryItem(name: "scope", value: MCPOAuthService.scope),
            URLQueryItem(name: "resource", value: resource),
        ]
        return try #require(components.string)
    }

    private func initializeRequest() -> MCPRequest {
        MCPRequest(
            jsonrpc: "2.0",
            id: .integer(1),
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("test-client"),
                    "version": .string("1.0.0"),
                ]),
            ])
        )
    }
}
