import Fluent
import Foundation
import Vapor

struct MCPController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("mcp", use: handle)
        routes.get("mcp") { _ -> Response in
            Response(status: .methodNotAllowed)
        }
        routes.delete("mcp") { _ in HTTPStatus.noContent }
    }

    func handle(req: Request) async throws -> Response {
        let request: MCPRequest
        do {
            request = try req.content.decode(MCPRequest.self)
        } catch {
            return try jsonResponse(MCPResponse(
                id: .null,
                error: MCPError(code: -32700, message: "Parse error")
            ))
        }
        guard request.jsonrpc == "2.0" else {
            return try jsonResponse(MCPResponse(
                id: request.id ?? .null,
                error: MCPError(code: -32600, message: "Invalid Request")
            ))
        }
        guard let id = request.id else {
            return Response(status: .accepted)
        }
        do {
            let result = try await dispatch(request, req: req)
            return try jsonResponse(MCPResponse(id: id, result: result))
        } catch let error as MCPProtocolError {
            return try jsonResponse(MCPResponse(
                id: id,
                error: MCPError(code: error.code, message: error.message)
            ))
        }
    }

    private func dispatch(_ request: MCPRequest, req: Request) async throws -> MCPJSONValue {
        switch request.method {
        case "initialize":
            return .object([
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)]),
                    "resources": .object([
                        "subscribe": .bool(false),
                        "listChanged": .bool(false),
                    ]),
                ]),
                "serverInfo": .object([
                    "name": .string("flowboard"),
                    "title": .string("Flowboard Workspace"),
                    "version": .string("0.1.0"),
                ]),
                "instructions": .string("Read the user's Flowboard boards, task descriptions, planning fields, grades, and linked Canvas course and assignment data. This server is read-only."),
            ])
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": .array(try toolDefinitions().map(MCPJSONValue.encoded))])
        case "tools/call":
            return try await callTool(params: request.params, req: req)
        case "resources/list":
            return try await listResources(req: req)
        case "resources/templates/list":
            return .object(["resourceTemplates": .array(try resourceTemplates().map(MCPJSONValue.encoded))])
        case "resources/read":
            return try await readResource(params: request.params, req: req)
        default:
            throw MCPProtocolError(code: -32601, message: "Method not found")
        }
    }

    private func callTool(params: MCPJSONValue?, req: Request) async throws -> MCPJSONValue {
        guard let params = params?.objectValue,
              let name = params["name"]?.stringValue else {
            throw MCPProtocolError(code: -32602, message: "Tool name is required")
        }
        let arguments = params["arguments"]?.objectValue ?? [:]
        let value: MCPJSONValue
        switch name {
        case "list_boards":
            value = try await MCPJSONValue.encoded(listBoards(arguments: arguments, req: req))
        case "get_board":
            value = try await MCPJSONValue.encoded(getBoard(arguments: arguments, req: req))
        case "search_tasks":
            value = try await MCPJSONValue.encoded(searchTasks(arguments: arguments, req: req))
        case "get_task":
            value = try await MCPJSONValue.encoded(getTask(arguments: arguments, req: req))
        case "get_canvas_data":
            value = try await MCPJSONValue.encoded(canvasData(req: req))
        default:
            throw MCPProtocolError(code: -32602, message: "Unknown tool: \(name)")
        }
        let resolved = try await resolve(value)
        let text = try prettyJSON(resolved)
        return try MCPJSONValue.encoded(MCPToolResult(
            content: [MCPTextContent(text: text)],
            structuredContent: resolved,
            isError: false
        ))
    }

    private func listResources(req: Request) async throws -> MCPJSONValue {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        let boards = try await Board.query(on: req.db)
            .filter(\.$id ~~ boardIDs)
            .sort(\.$name, .ascending)
            .all()
        var resources = try boards.map { board in
            MCPResource(
                uri: "flowboard://boards/\(try board.requireID())",
                name: "board-\(board.slug)",
                title: board.name,
                description: board.description ?? "Flowboard board with its tasks and workflow definitions.",
                mimeType: "application/json"
            )
        }
        resources.append(MCPResource(
            uri: "flowboard://canvas",
            name: "canvas",
            title: "Canvas data",
            description: "Canvas connections, courses, assignments, submissions, deadlines, and grades linked to Flowboard.",
            mimeType: "application/json"
        ))
        return .object(["resources": .array(try resources.map(MCPJSONValue.encoded))])
    }

    private func readResource(params: MCPJSONValue?, req: Request) async throws -> MCPJSONValue {
        guard let uri = params?.objectValue?["uri"]?.stringValue else {
            throw MCPProtocolError(code: -32602, message: "Resource URI is required")
        }
        let value: MCPJSONValue
        if uri == "flowboard://canvas" {
            value = try await MCPJSONValue.encoded(canvasData(req: req))
        } else if let id = resourceID(uri, prefix: "flowboard://boards/") {
            value = try await MCPJSONValue.encoded(getBoard(arguments: ["board_id": .string(id)], req: req))
        } else if let id = resourceID(uri, prefix: "flowboard://tasks/") {
            value = try await MCPJSONValue.encoded(getTask(arguments: ["task_id": .string(id)], req: req))
        } else {
            throw MCPProtocolError(code: -32002, message: "Resource not found")
        }
        let resolved = try await resolve(value)
        return try MCPJSONValue.encoded([
            MCPResourceContents(uri: uri, text: try prettyJSON(resolved)),
        ]).wrapped(key: "contents")
    }

    private func listBoards(arguments: [String: MCPJSONValue], req: Request) async throws -> [MCPBoardSummary] {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        var query = Board.query(on: req.db).filter(\.$id ~~ boardIDs).with(\.$tasks)
        if let archived = arguments["archived"]?.boolValue {
            query = query.filter(\.$isArchived == archived)
        } else {
            query = query.filter(\.$isArchived == false)
        }
        if let search = clean(arguments["query"]?.stringValue) {
            query = query.group(.or) { matches in
                matches.filter(\.$name, .custom("LIKE"), "%\(search)%")
                    .filter(\.$description, .custom("LIKE"), "%\(search)%")
            }
        }
        let boards = try await query.sort(\.$name, .ascending).all()
        let canvasLinks = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id ~~ boards.compactMap(\.id))
            .all()
        let linksByBoard = Dictionary(uniqueKeysWithValues: canvasLinks.map { ($0.$board.id, $0) })
        return try boards.map { board in
            let tasks = board.tasks
            return MCPBoardSummary(
                id: try board.requireID(),
                name: board.name,
                slug: board.slug,
                description: board.description,
                isArchived: board.isArchived,
                taskCount: tasks.count,
                completedCount: tasks.filter { board.isCompleted($0.status) }.count,
                canvasCourse: linksByBoard[try board.requireID()].map(canvasCourseSummary),
                createdAt: board.createdAt,
                updatedAt: board.updatedAt
            )
        }
    }

    private func getBoard(arguments: [String: MCPJSONValue], req: Request) async throws -> MCPBoardDetail {
        let boardID = try requiredUUID(arguments, key: "board_id")
        let userID = try req.auth.require(User.self).requireID()
        let access = try await BoardAccessService.require(
            boardID: boardID,
            userID: userID,
            permission: .view,
            on: req.db
        )
        let tasks = try await Task.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .sort(\.$position, .ascending)
            .all()
        let course = try await CanvasCourseLink.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .first()
        let assignmentLinks = try await CanvasAssignmentLink.query(on: req.db)
            .filter(\.$task.$id ~~ tasks.compactMap(\.id))
            .all()
        let linksByTask = Dictionary(uniqueKeysWithValues: assignmentLinks.map { ($0.$task.id, $0) })
        let board = access.board
        return MCPBoardDetail(
            id: boardID,
            name: board.name,
            slug: board.slug,
            description: board.description,
            isArchived: board.isArchived,
            propertyDefinitions: board.propertyDefinitions ?? [],
            statusDefinitions: board.taskStatuses,
            severityDefinitions: board.taskSeverities,
            canvasCourse: course.map(canvasCourseSummary),
            tasks: try tasks.map { task in
                try taskDetail(task, board: board, canvasLink: task.id.flatMap { linksByTask[$0] })
            },
            createdAt: board.createdAt,
            updatedAt: board.updatedAt
        )
    }

    private func searchTasks(arguments: [String: MCPJSONValue], req: Request) async throws -> [MCPTaskDetail] {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = try await BoardAccessService.boardIDs(for: userID, on: req.db)
        var query = Task.query(on: req.db)
            .filter(\.$board.$id ~~ boardIDs)
            .with(\.$board)
        if arguments["include_archived"]?.boolValue != true {
            query = query.filter(\.$isArchived == false)
        }
        if let boardIDValue = arguments["board_id"]?.stringValue,
           let boardID = UUID(uuidString: boardIDValue) {
            guard boardIDs.contains(boardID) else { throw MCPProtocolError(code: -32002, message: "Board not found") }
            query = query.filter(\.$board.$id == boardID)
        }
        if let status = clean(arguments["status"]?.stringValue) {
            query = query.filter(\.$statusValue == status)
        }
        if let search = clean(arguments["query"]?.stringValue) {
            query = query.group(.or) { matches in
                matches.filter(\.$title, .custom("LIKE"), "%\(search)%")
                    .filter(\.$description, .custom("LIKE"), "%\(search)%")
            }
        }
        let limit = min(max(arguments["limit"]?.intValue ?? 25, 1), 100)
        let tasks = try await query.sort(\.$dueAt, .ascending).limit(limit).all()
        let links = try await CanvasAssignmentLink.query(on: req.db)
            .filter(\.$task.$id ~~ tasks.compactMap(\.id))
            .all()
        let linksByTask = Dictionary(uniqueKeysWithValues: links.map { ($0.$task.id, $0) })
        return try tasks.map { task in
            try taskDetail(task, board: task.board, canvasLink: task.id.flatMap { linksByTask[$0] })
        }
    }

    private func getTask(arguments: [String: MCPJSONValue], req: Request) async throws -> MCPTaskDetail {
        let taskID = try requiredUUID(arguments, key: "task_id")
        guard let task = try await Task.query(on: req.db)
            .filter(\.$id == taskID)
            .with(\.$board)
            .first() else {
            throw MCPProtocolError(code: -32002, message: "Task not found")
        }
        let userID = try req.auth.require(User.self).requireID()
        _ = try await BoardAccessService.require(
            boardID: task.$board.id,
            userID: userID,
            permission: .view,
            on: req.db
        )
        let link = try await CanvasAssignmentLink.query(on: req.db)
            .filter(\.$task.$id == taskID)
            .first()
        return try taskDetail(task, board: task.board, canvasLink: link)
    }

    private func canvasData(req: Request) async throws -> [MCPCanvasConnectionSummary] {
        let userID = try req.auth.require(User.self).requireID()
        let boardIDs = Set(try await BoardAccessService.boardIDs(for: userID, on: req.db))
        let connections = try await CanvasConnection.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .ascending)
            .all()
        var result: [MCPCanvasConnectionSummary] = []
        for connection in connections {
            let courses = try await CanvasCourseLink.query(on: req.db)
                .filter(\.$connection.$id == connection.requireID())
                .with(\.$board)
                .all()
                .filter { boardIDs.contains($0.$board.id) }
            var courseDetails: [MCPCanvasCourseDetail] = []
            for course in courses {
                let links = try await CanvasAssignmentLink.query(on: req.db)
                    .filter(\.$courseLink.$id == course.requireID())
                    .with(\.$task) { $0.with(\.$board) }
                    .all()
                courseDetails.append(MCPCanvasCourseDetail(
                    id: try course.requireID(),
                    boardID: course.$board.id,
                    boardName: course.board.name,
                    remoteCourseID: course.remoteCourseID,
                    canvasCourseURL: course.canvasCourseURL,
                    courseCode: course.courseCode,
                    termName: course.termName,
                    currentScore: course.currentScore,
                    currentGrade: course.currentGrade,
                    syncArchived: course.syncArchived,
                    assignments: try links.map { try taskDetail($0.task, board: $0.task.board, canvasLink: $0) }
                ))
            }
            result.append(MCPCanvasConnectionSummary(
                id: try connection.requireID(),
                canvasOrigin: connection.canvasOrigin,
                lastSnapshotID: connection.lastSnapshotID,
                lastCapturedAt: connection.lastCapturedAt,
                lastSuccessfulSyncAt: connection.lastSuccessfulSyncAt,
                lastErrorSummary: connection.lastErrorSummary,
                courses: courseDetails
            ))
        }
        return result
    }

    private func taskDetail(_ task: Task, board: Board, canvasLink: CanvasAssignmentLink?) throws -> MCPTaskDetail {
        MCPTaskDetail(
            id: try task.requireID(),
            publicID: task.publicID,
            boardID: task.$board.id,
            boardName: board.name,
            title: task.title,
            description: task.description,
            status: task.statusValue,
            severity: task.priorityValue,
            position: task.position,
            labels: task.labels,
            startAt: task.startAt,
            dueAt: task.dueAt,
            dueTime: task.dueTime,
            estimatedMinutes: task.estimatedMinutes,
            gradeEarned: task.gradeEarned,
            gradePossible: task.gradePossible,
            assigneeID: task.$assignee.id,
            creatorID: task.$creator.id,
            properties: task.properties ?? [:],
            isArchived: task.isArchived,
            browserPath: task.browserPath,
            canvasAssignment: canvasLink.map(canvasAssignmentSummary),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    private func canvasCourseSummary(_ link: CanvasCourseLink) -> MCPCanvasCourseSummary {
        MCPCanvasCourseSummary(
            remoteCourseID: link.remoteCourseID,
            canvasCourseURL: link.canvasCourseURL,
            courseCode: link.courseCode,
            termName: link.termName,
            currentScore: link.currentScore,
            currentGrade: link.currentGrade,
            syncArchived: link.syncArchived
        )
    }

    private func canvasAssignmentSummary(_ link: CanvasAssignmentLink) -> MCPCanvasAssignmentSummary {
        MCPCanvasAssignmentSummary(
            remoteAssignmentID: link.remoteAssignmentID,
            canvasAssignmentURL: link.canvasAssignmentURL,
            submissionState: link.submissionState,
            gradeLabel: link.gradeLabel,
            submittedAt: link.submittedAt,
            isLate: link.isLate,
            isMissing: link.isMissing,
            isExcused: link.isExcused,
            redoRequested: link.redoRequested,
            syncArchived: link.syncArchived,
            canvasControlsCompletion: link.canvasControlsCompletion
        )
    }

    private func toolDefinitions() throws -> [MCPToolDefinition] {
        let readOnly = MCPToolAnnotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
        return [
            MCPToolDefinition(name: "list_boards", title: "List boards", description: "List accessible Flowboard boards with descriptions, completion counts, and linked Canvas course summaries.", inputSchema: schema(properties: ["query": stringProperty("Search board names and descriptions."), "archived": booleanProperty("Filter by archive state; omitted means active boards.")]), annotations: readOnly),
            MCPToolDefinition(name: "get_board", title: "Get board", description: "Get a board's full description, workflow and custom-field definitions, every task, and linked Canvas metadata.", inputSchema: schema(properties: ["board_id": stringProperty("Flowboard board UUID.")], required: ["board_id"]), annotations: readOnly),
            MCPToolDefinition(name: "search_tasks", title: "Search tasks", description: "Search accessible tasks by title or description and return planning, grading, custom-field, and Canvas assignment data.", inputSchema: schema(properties: ["query": stringProperty("Text in title or description."), "board_id": stringProperty("Optional board UUID."), "status": stringProperty("Optional board-specific status ID."), "include_archived": booleanProperty("Include archived tasks."), "limit": integerProperty("Maximum results from 1 to 100.")]), annotations: readOnly),
            MCPToolDefinition(name: "get_task", title: "Get task", description: "Get one task including its complete description, dates, estimate, grade, custom properties, and Canvas assignment status.", inputSchema: schema(properties: ["task_id": stringProperty("Flowboard task UUID.")], required: ["task_id"]), annotations: readOnly),
            MCPToolDefinition(name: "get_canvas_data", title: "Get Canvas data", description: "Get all Canvas connections owned by the user, linked courses, assignments, submission states, deadlines, scores, and grades. Sync credentials are never returned.", inputSchema: schema(properties: [:]), annotations: readOnly),
        ]
    }

    private func resourceTemplates() -> [MCPResourceTemplate] {
        [
            MCPResourceTemplate(uriTemplate: "flowboard://boards/{board_id}", name: "board", title: "Flowboard board", description: "A complete board with tasks, descriptions, workflow fields, and Canvas metadata.", mimeType: "application/json"),
            MCPResourceTemplate(uriTemplate: "flowboard://tasks/{task_id}", name: "task", title: "Flowboard task", description: "A complete task with description, planning data, grade, and Canvas metadata.", mimeType: "application/json"),
        ]
    }

    private func schema(properties: [String: MCPJSONValue], required: [String] = []) -> MCPJSONValue {
        var value: [String: MCPJSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty { value["required"] = .array(required.map(MCPJSONValue.string)) }
        return .object(value)
    }

    private func stringProperty(_ description: String) -> MCPJSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private func booleanProperty(_ description: String) -> MCPJSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    private func integerProperty(_ description: String) -> MCPJSONValue {
        .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(100), "description": .string(description)])
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    private func requiredUUID(_ arguments: [String: MCPJSONValue], key: String) throws -> UUID {
        guard let value = arguments[key]?.stringValue, let id = UUID(uuidString: value) else {
            throw MCPProtocolError(code: -32602, message: "\(key) must be a UUID")
        }
        return id
    }

    private func resourceID(_ uri: String, prefix: String) -> String? {
        guard uri.hasPrefix(prefix) else { return nil }
        return String(uri.dropFirst(prefix.count))
    }

    private func resolve<T>(_ value: T) async throws -> T { value }

    private func prettyJSON(_ value: MCPJSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct MCPProtocolError: Error {
    let code: Int
    let message: String
}

private extension MCPJSONValue {
    func wrapped(key: String) -> MCPJSONValue {
        .object([key: self])
    }
}
