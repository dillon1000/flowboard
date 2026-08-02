@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Flowboard Tap actions")
struct TapActionTests {
    @Test("A bearer capability creates one task for a retried request")
    func createTaskIsIdempotent() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let board = try #require(try await Board.find(session.boardID, on: app.db))
            board.propertyDefinitions = [
                BoardPropertyDefinition(
                    id: "location",
                    name: "Location",
                    type: .text,
                    options: []
                )
            ]
            try await board.update(on: app.db)
            let created = try await TapActionService.create(
                board: board,
                definition: createTaskDefinition(cooldownSeconds: 0),
                on: app.db
            )
            let input = TapExecutionRequest(
                token: created.rawToken,
                requestID: UUID(),
                task: scannerTaskInput()
            )

            let preparation = try await prepare(
                TapPreparationRequest(token: created.rawToken),
                on: app
            )
            #expect(preparation.status == .ok)
            let taskForm = try #require(try preparation.content.decode(TapPreparationResponse.self).task)
            #expect(taskForm.properties.map(\.id) == ["location"])

            let first = try await execute(input, on: app)
            #expect(first.status == .ok)
            let firstResult = try first.content.decode(TapExecutionResponse.self)
            #expect(firstResult.message == "Task created.")
            #expect(firstResult.actionDescription == "Leave the clipboard at the loading dock.")
            let createdTask = try #require(
                try await Task.query(on: app.db)
                    .filter(\.$board.$id == session.boardID)
                    .filter(\.$title == "Scanner inspection")
                    .first()
            )
            #expect(createdTask.$description.value == "Entered on the scanner phone.")
            #expect(createdTask.labels == ["NFC", "intake"])
            #expect(createdTask.startAt != nil)
            #expect(createdTask.dueAt != nil)
            #expect(createdTask.properties?["location"] == "Front desk")

            let retry = try await execute(input, on: app)
            #expect(retry.status == .ok)
            #expect(
                try await Task.query(on: app.db)
                    .filter(\.$board.$id == session.boardID)
                    .filter(\.$title == "Scanner inspection")
                    .count() == 1
            )
            #expect(try await TapExecution.query(on: app.db).count() == 1)
            let storedAction = try #require(
                try await TapAction.find(created.action.requireID(), on: app.db)
            )
            #expect(storedAction.useCount == 1)
            #expect(storedAction.lastUsedAt != nil)

            let secondAction = try await TapActionService.create(
                board: board,
                definition: createTaskDefinition(cooldownSeconds: 0),
                on: app.db
            )
            let secondResult = try await execute(
                TapExecutionRequest(
                    token: secondAction.rawToken,
                    requestID: input.requestID,
                    task: scannerTaskInput()
                ),
                on: app
            )
            #expect(secondResult.status == .ok)
            #expect(try await TapExecution.query(on: app.db).count() == 2)
        }
    }

    @Test("A bearer capability updates its assigned task without authentication")
    func updateTaskWithoutAuthentication() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let board = try #require(try await Board.find(session.boardID, on: app.db))
            let task = Task(
                boardID: session.boardID,
                title: "Physical work order",
                status: .backlog,
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let configuration = TapActionConfiguration(
                title: nil,
                description: nil,
                status: TaskStatus.done.rawValue,
                priority: nil,
                labels: []
            )
            let created = try await TapActionService.create(
                board: board,
                definition: TapActionService.Definition(
                    name: "Finish work order",
                    displayDescription: "The work order is now complete.",
                    kind: .updateTask,
                    targetTaskID: task.requireID(),
                    configuration: configuration,
                    expiresAt: nil,
                    maxUses: nil,
                    cooldownSeconds: 0
                ),
                on: app.db
            )

            let response = try await execute(
                TapExecutionRequest(token: created.rawToken, requestID: UUID()),
                on: app
            )

            #expect(response.status == .ok)
            #expect(try response.content.decode(TapExecutionResponse.self).message == "Task updated.")
            #expect(try #require(try await Task.find(task.requireID(), on: app.db)).status == .done)
        }
    }

    @Test("Disabled, expired, and exhausted capabilities cannot change tasks")
    func lifecycleLimitsStopExecution() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let board = try #require(try await Board.find(session.boardID, on: app.db))

            let disabled = try await TapActionService.create(
                board: board,
                definition: createTaskDefinition(cooldownSeconds: 0),
                on: app.db
            )
            disabled.action.isEnabled = false
            try await disabled.action.update(on: app.db)
            #expect(
                try await execute(
                    TapExecutionRequest(token: disabled.rawToken, requestID: UUID()),
                    on: app
                ).status == .gone
            )

            let expired = try await TapActionService.create(
                board: board,
                definition: createTaskDefinition(cooldownSeconds: 0),
                on: app.db
            )
            expired.action.expiresAt = Date(timeIntervalSinceNow: -60)
            try await expired.action.update(on: app.db)
            #expect(
                try await execute(
                    TapExecutionRequest(token: expired.rawToken, requestID: UUID()),
                    on: app
                ).status == .gone
            )

            let limited = try await TapActionService.create(
                board: board,
                definition: createTaskDefinition(maxUses: 1, cooldownSeconds: 0),
                on: app.db
            )
            #expect(
                try await execute(
                    TapExecutionRequest(
                        token: limited.rawToken,
                        requestID: UUID(),
                        task: scannerTaskInput()
                    ),
                    on: app
                ).status == .ok
            )
            #expect(
                try await execute(
                    TapExecutionRequest(token: limited.rawToken, requestID: UUID()),
                    on: app
                ).status == .gone
            )
        }
    }

    @Test("Tap URLs use URL-safe secrets and stay below 504 bytes")
    func URLLengthLimit() throws {
        let token = TapTokenService.generate().raw
        let URL = try TapTokenService.makeURL(
            rawToken: token,
            baseURL: "https://tap.flowboard.example/t"
        )

        #expect(TapTokenService.isWellFormed(token))
        #expect(URL.utf8.count < 504)
        #expect(URL.hasSuffix("#\(token)"))
        #expect(throws: (any Error).self) {
            try TapTokenService.makeURL(
                rawToken: token,
                baseURL: "https://example.com/\(String(repeating: "x", count: 500))"
            )
        }
    }

    @Test("The public Tap runner is small, cacheable, and session-free")
    func publicRunner() async throws {
        try await withApp(configure: configure) { app in
            let response = try await app.testing().sendRequest(.GET, "t")
            let page = response.body.string

            #expect(response.status == .ok)
            #expect(response.headers.first(name: .cacheControl)?.contains("public") == true)
            #expect(response.headers.first(name: "Referrer-Policy") == "no-referrer")
            let CSS = try text(between: "<style>", and: "</style>", in: page)
            #expect(CSS.split(separator: "\n").count < 400)
            #expect(page.utf8.count < 20_000)
            #expect(!page.contains("/assets/"))
            #expect(page.contains("/api/v1/taps/prepare"))
            #expect(page.contains("/api/v1/taps/execute"))
            #expect(page.contains("/tagneedsrotation.svg"))
            #expect(page.contains("/scanerror.svg"))
            let fragmentRemoval = try #require(page.range(of: "history.replaceState")?.lowerBound)
            let preparationRequest = try #require(page.range(of: "fetch('/api/v1/taps/prepare")?.lowerBound)
            #expect(fragmentRemoval < preparationRequest)
        }
    }

    @Test("Board administrators can create, reassign, disable, and rotate Tap actions")
    func managementLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let settings = try await app.testing().sendRequest(
                .GET,
                "app/boards/\(session.boardID)/settings",
                headers: ["Cookie": session.cookie]
            )
            let csrfToken = try csrfToken(from: settings.body.string)
            let create = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/tap-actions",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        [
                            "name": "Dock inspection",
                            "displayDescription": "Leave the clipboard at the loading dock.",
                            "kind": "create_task",
                            "targetTaskID": "",
                            "title": "Inspect the loading dock",
                            "description": "Created by a physical tag.",
                            "status": "backlog",
                            "priority": "high",
                            "labels": "NFC, inspection",
                            "expiresAt": "",
                            "maxUses": "5",
                            "cooldownSeconds": "2",
                        ],
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(create.status == .created)
            #expect(create.headers.first(name: .cacheControl) == "no-store")
            let createPage = create.body.string
            let tagURL = try text(
                between: #"<code class="tap-url-secret" data-tap-provision-target="url">"#,
                and: "</code>",
                in: createPage
            )
            #expect(tagURL.utf8.count < TapTokenService.maximumURLByteCount)
            #expect(tagURL.contains("/t#fbt_"))
            #expect(createPage.contains("Write NFC tag"))

            let action = try #require(
                try await TapAction.query(on: app.db)
                    .filter(\.$board.$id == session.boardID)
                    .first()
            )
            let firstTokenHash = action.tokenHash
            #expect(action.name == "Dock inspection")
            #expect(action.displayDescription == "Leave the clipboard at the loading dock.")
            #expect(action.kind == .createTask)
            #expect(action.configuration.labels.isEmpty)
            #expect(action.maxUses == 5)
            #expect(!action.tokenHash.contains(String(tagURL.suffix(36))))

            let laterSettings = try await app.testing().sendRequest(
                .GET,
                "app/boards/\(session.boardID)/settings",
                headers: ["Cookie": session.cookie]
            )
            #expect(!laterSettings.body.string.contains(tagURL))

            let task = Task(
                boardID: session.boardID,
                title: "Reassigned work order",
                position: 1_000,
                creatorID: session.userID
            )
            try await task.create(on: app.db)
            let update = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/tap-actions/\(action.requireID())/update",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        [
                            "name": "Finish work order",
                            "displayDescription": "This work order is now complete.",
                            "kind": "update_task",
                            "targetTaskID": try task.requireID().uuidString,
                            "title": "",
                            "description": "",
                            "status": "done",
                            "priority": "medium",
                            "labels": "",
                            "expiresAt": "",
                            "maxUses": "",
                            "cooldownSeconds": "3",
                        ],
                        as: .urlEncodedForm
                    )
                }
            )
            #expect(update.status == .seeOther)
            let reassigned = try #require(try await TapAction.find(action.requireID(), on: app.db))
            #expect(reassigned.kind == .updateTask)
            #expect(reassigned.displayDescription == "This work order is now complete.")
            #expect(reassigned.$targetTask.id == task.id)
            #expect(reassigned.tokenHash == firstTokenHash)

            let disabled = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/tap-actions/\(action.requireID())/toggle",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ]
            )
            #expect(disabled.status == .seeOther)
            #expect(!(try #require(try await TapAction.find(action.requireID(), on: app.db))).isEnabled)

            let rotated = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/tap-actions/\(action.requireID())/rotate",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ]
            )
            #expect(rotated.status == .ok)
            #expect(rotated.headers.first(name: .cacheControl) == "no-store")
            #expect(
                try #require(try await TapAction.find(action.requireID(), on: app.db)).tokenHash
                    != firstTokenHash
            )
        }
    }

    private func createTaskDefinition(
        maxUses: Int? = nil,
        cooldownSeconds: Int
    ) -> TapActionService.Definition {
        TapActionService.Definition(
            name: "Create inspection",
            displayDescription: "Leave the clipboard at the loading dock.",
            kind: .createTask,
            targetTaskID: nil,
            configuration: TapActionConfiguration(
                title: "Inspect the loading dock",
                description: "Created from the dock NFC tag.",
                status: TaskStatus.backlog.rawValue,
                priority: TaskPriority.high.rawValue,
                labels: ["NFC"]
            ),
            expiresAt: nil,
            maxUses: maxUses,
            cooldownSeconds: cooldownSeconds
        )
    }

    private func scannerTaskInput() -> TapTaskInput {
        TapTaskInput(
            title: "Scanner inspection",
            description: "Entered on the scanner phone.",
            status: TaskStatus.backlog.rawValue,
            priority: TaskPriority.high.rawValue,
            labels: ["NFC", "intake"],
            startAt: "2026-08-02",
            dueAt: "2026-08-03",
            properties: ["location": "Front desk"]
        )
    }

    private func execute(
        _ input: TapExecutionRequest,
        on app: Application
    ) async throws -> TestingHTTPResponse {
        try await app.testing().sendRequest(
            .POST,
            "api/v1/taps/execute",
            beforeRequest: { request in
                try request.content.encode(input)
            }
        )
    }

    private func prepare(
        _ input: TapPreparationRequest,
        on app: Application
    ) async throws -> TestingHTTPResponse {
        try await app.testing().sendRequest(
            .POST,
            "api/v1/taps/prepare",
            beforeRequest: { request in
                try request.content.encode(input)
            }
        )
    }

    private func csrfToken(from page: String) throws -> String {
        let marker = #"name="csrf-token" content=""#
        let start = try #require(page.range(of: marker)?.upperBound)
        let end = try #require(page[start...].firstIndex(of: "\""))
        return String(page[start..<end])
    }

    private func text(between startMarker: String, and endMarker: String, in page: String) throws -> String {
        let start = try #require(page.range(of: startMarker)?.upperBound)
        let end = try #require(page[start...].range(of: endMarker)?.lowerBound)
        return String(page[start..<end])
    }
}
