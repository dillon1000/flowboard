@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Custom fields")
struct CustomFieldTests {
    @Test("Select definitions create stable options")
    func selectDefinitionsCreateOptions() async throws {
        try await withApp(configure: configure) { app in
            let session = try await register(on: app)
            let settings = try await app.testing().sendRequest(
                .GET,
                "app/boards/\(session.boardID)/settings",
                headers: ["Cookie": session.cookie]
            )
            let csrfToken = try csrfToken(from: settings.body.string)
            let response = try await app.testing().sendRequest(
                .POST,
                "app/boards/\(session.boardID)/properties",
                headers: [
                    "Cookie": session.cookie,
                    "X-CSRF-TOKEN": csrfToken,
                ],
                beforeRequest: { request in
                    try request.content.encode(
                        [
                            "name": "Regions",
                            "type": "multi_select",
                            "options": "North America, Europe, Asia Pacific",
                        ],
                        as: .urlEncodedForm
                    )
                }
            )

            #expect(response.status == .seeOther)
            let board = try #require(try await Board.find(session.boardID, on: app.db))
            let definition = try #require(board.propertyDefinitions?.first)
            #expect(definition.type == .multiSelect)
            #expect(definition.options.map(\.id) == ["north-america", "europe", "asia-pacific"])
            #expect(definition.options.map(\.name) == ["North America", "Europe", "Asia Pacific"])

            let task = Task(
                boardID: session.boardID,
                title: "Plan launch regions",
                position: 1_000,
                creatorID: session.userID
            )
            task.properties = [definition.id: #"["north-america","europe"]"#]
            try await task.create(on: app.db)
            let taskPage = try await app.testing().sendRequest(
                .GET,
                String(task.browserPath.dropFirst()),
                headers: ["Cookie": session.cookie]
            )
            #expect(taskPage.status == .ok)
            expectContains(taskPage.body.string, "North America, Europe")
            expectContains(taskPage.body.string, #"name="property-\#(definition.id)-north-america""#)
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

    private func definition(
        _ type: BoardPropertyType,
        options: [BoardPropertyOption] = []
    ) -> BoardPropertyDefinition {
        BoardPropertyDefinition(id: "field", name: "Field", type: type, options: options)
    }

    private func csrfToken(from page: String) throws -> String {
        let marker = #"name="csrf-token" content=""#
        let start = try #require(page.range(of: marker)?.upperBound)
        let end = try #require(page[start...].firstIndex(of: "\""))
        return String(page[start..<end])
    }
}
