@testable import App
import Fluent
import Testing
import Vapor
import VaporTesting

@Suite("Custom fields")
struct CustomFieldTests {
    @Test("Select definitions create stable options and page data")
    func selectDefinitionsCreateOptions() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let response = try await app.testing().sendRequest(
                .POST,
                "api/v1/boards/\(session.boardID)/properties",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(
                        CreatePropertyTestRequest(
                            name: "Regions",
                            type: .multiSelect,
                            options: ["North America", "Europe", "Asia Pacific"]
                        )
                    )
                }
            )
            #expect(response.status == .ok)

            let board = try #require(try await Board.find(session.boardID, on: app.db))
            let definition = try #require(board.propertyDefinitions?.first)
            #expect(definition.type == .multiSelect)
            #expect(definition.options.map(\.id) == ["north-america", "europe", "asia-pacific"])
            #expect(definition.options.map(\.name) == ["North America", "Europe", "Asia Pacific"])
            let primaryRegion = BoardPropertyDefinition(
                id: "primary-region",
                name: "Primary region",
                type: .select,
                options: definition.options
            )
            board.propertyDefinitions = [definition, primaryRegion]
            try await board.update(on: app.db)

            let task = Task(
                boardID: session.boardID,
                title: "Plan launch regions",
                position: 1_000,
                creatorID: session.userID
            )
            task.properties = [
                definition.id: #"["north-america","europe"]"#,
                primaryRegion.id: "europe",
            ]
            try await task.create(on: app.db)
            let taskData = try await app.testing().sendRequest(
                .GET,
                "api/v1/workspace/tasks/\(task.publicID)",
                headers: ["Cookie": session.cookie]
            )
            #expect(taskData.status == .ok)
            expectContains(taskData.body.string, "North America, Europe")
            expectContains(taskData.body.string, #""id":"north-america""#)
            expectContains(taskData.body.string, #""id":"primary-region""#)
            expectContains(taskData.body.string, #""inputValue":"europe""#)
        }
    }

    @Test("Values conform to their field types")
    func valuesConformToFieldTypes() {
        let options = [
            BoardPropertyOption(id: "alpha", name: "Alpha", color: "gray"),
            BoardPropertyOption(id: "beta", name: "Beta", color: "blue"),
        ]

        #expect(definition(.number).normalizedValue("12.5") == "12.5")
        #expect(definition(.number).normalizedValue("twelve") == nil)
        #expect(definition(.select, options: options).normalizedValue("alpha") == "alpha")
        #expect(definition(.select, options: options).normalizedValue("gamma") == nil)
        #expect(
            definition(.multiSelect, options: options).normalizedValue(#"["beta","alpha","other"]"#)
                == #"["alpha","beta"]"#
        )
        #expect(definition(.date).normalizedValue("2026-07-31") == "2026-07-31")
        #expect(definition(.date).normalizedValue("2026-02-30") == nil)
        #expect(definition(.checkbox).normalizedValue("true") == "true")
        #expect(definition(.checkbox).normalizedValue("false") == nil)
        #expect(definition(.url).normalizedValue("https://example.com/path") == "https://example.com/path")
        #expect(definition(.url).normalizedValue("javascript:alert(1)") == nil)
        #expect(definition(.email).normalizedValue("person@example.com") == "person@example.com")
        #expect(definition(.email).normalizedValue("person") == nil)
        #expect(
            definition(.person).normalizedValue("85F3AD1A-F793-4A1F-8126-17CA8F6C4C26")
                == "85f3ad1a-f793-4a1f-8126-17ca8f6c4c26"
        )
    }

    @Test("Field names update and deletion removes stored values")
    func fieldLifecycle() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let board = try #require(try await Board.find(session.boardID, on: app.db))
            let definition = BoardPropertyDefinition(
                id: "reading-kind",
                name: "Reading knd",
                type: .text,
                options: []
            )
            board.propertyDefinitions = [definition]
            try await board.update(on: app.db)
            let task = Task(
                boardID: session.boardID,
                title: "Read chapter four",
                position: 1_000,
                creatorID: session.userID
            )
            task.properties = [definition.id: "Textbook"]
            try await task.create(on: app.db)

            let updated = try await app.testing().sendRequest(
                .PATCH,
                "api/v1/boards/\(session.boardID)/properties/\(definition.id)",
                headers: ["Cookie": session.cookie],
                beforeRequest: { request in
                    try request.content.encode(UpdatePropertyTestRequest(name: "Reading kind"))
                }
            )
            #expect(updated.status == .ok)
            let updatedBoard = try #require(try await Board.find(session.boardID, on: app.db))
            #expect(updatedBoard.propertyDefinitions?.first?.name == "Reading kind")

            let deleted = try await app.testing().sendRequest(
                .DELETE,
                "api/v1/boards/\(session.boardID)/properties/\(definition.id)",
                headers: ["Cookie": session.cookie]
            )
            #expect(deleted.status == .noContent)
            let deletedBoard = try #require(try await Board.find(session.boardID, on: app.db))
            let deletedTask = try #require(try await Task.find(task.id, on: app.db))
            #expect(deletedBoard.propertyDefinitions?.isEmpty == true)
            #expect(deletedTask.properties?[definition.id] == nil)
        }
    }

    private func definition(
        _ type: BoardPropertyType,
        options: [BoardPropertyOption] = []
    ) -> BoardPropertyDefinition {
        BoardPropertyDefinition(id: "field", name: "Field", type: type, options: options)
    }
}

private struct CreatePropertyTestRequest: Content {
    let name: String
    let type: BoardPropertyType
    let options: [String]
}

private struct UpdatePropertyTestRequest: Content {
    let name: String
}
