@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Workspace page-data API")
struct WorkspacePageAPITests {
    @Test("Workspace data requires a browser session")
    func requiresSession() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "api/v1/workspace")

            #expect(response.status == .unauthorized)
        }
    }

    @Test("Overview data includes the signed-in workspace")
    func overviewData() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let response = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace",
                headers: ["Cookie": session.cookie]
            )

            #expect(response.status == .ok)
            #expect(response.headers.contentType == .json)
            expectContains(response.body.string, #""userName":"Test User""#)
            expectContains(response.body.string, #""documentTitle":"This week · Flowboard""#)
            expectContains(response.body.string, session.boardID.uuidString)
        }
    }

    @Test("Board and task routes return frontend destinations")
    func routeData() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let boardResponse = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/boards/\(session.boardID)",
                headers: ["Cookie": session.cookie]
            )
            #expect(boardResponse.status == .ok)
            expectContains(boardResponse.body.string, #""href":"/app/boards/"#)

            let task = Task(
                publicID: "a1b2c3",
                boardID: session.boardID,
                title: "Ship the Svelte frontend",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let taskResponse = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/tasks/ship-the-svelte-frontend-a1b2c3",
                headers: ["Cookie": session.cookie]
            )

            #expect(taskResponse.status == .ok)
            expectContains(taskResponse.body.string, "Ship the Svelte frontend")
            expectContains(taskResponse.body.string, task.browserPath)
        }
    }

    @Test("Board data exposes administration capability by role")
    func boardAdministrationCapability() async throws {
        try await withApp(configure: configure) { app in
            let owner = try await register(on: app)
            let viewer = try await register(on: app)
            try await BoardMember(
                boardID: owner.boardID,
                userID: viewer.userID,
                role: .viewer
            ).create(on: app.db)
            let viewID = try #require(
                try await BoardView.query(on: app.db)
                    .filter(\.$board.$id == owner.boardID)
                    .first()?
                    .requireID()
            )
            let path = "api/v1/workspace/boards/\(owner.boardID)/views/\(viewID)"

            let ownerResponse = try await app.testing().sendRequest(
                .GET,
                path,
                headers: ["Cookie": owner.cookie]
            )
            #expect(ownerResponse.status == .ok)
            expectContains(ownerResponse.body.string, #""canAdmin":true"#)

            let viewerResponse = try await app.testing().sendRequest(
                .GET,
                path,
                headers: ["Cookie": viewer.cookie]
            )
            #expect(viewerResponse.status == .ok)
            expectContains(viewerResponse.body.string, #""canAdmin":false"#)
        }
    }

    @Test("Auth configuration is public")
    func authConfiguration() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "api/v1/auth/config")

            #expect(response.status == .ok)
            let configuration = try response.content.decode(AuthConfigurationResponse.self)
            #expect(configuration.oauthEnabled == (app.oauthConfiguration != nil))
            #expect(configuration.oauthProviderName == (app.oauthConfiguration?.providerName ?? "OAuth"))
        }
    }
}
