import Vapor

/// Serves the restricted extension status and snapshot routes.
struct CanvasSyncController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("status", use: status)
        routes.on(.POST, "sync", body: .collect(maxSize: "5mb"), use: sync)
    }

    func status(req: Request) throws -> CanvasIntegrationStatusResponse {
        CanvasIntegrationStatusResponse(
            connection: try CanvasConnectionResponse(
                connection: req.auth.require(CanvasConnection.self)
            )
        )
    }

    func sync(req: Request) async throws -> CanvasSyncResponse {
        let startedAt = Date()
        let connection = try req.auth.require(CanvasConnection.self)
        let connectionID = try connection.requireID()
        do {
            let snapshot = try req.content.decode(CanvasSyncSnapshotV1.self)
            let response = try await CanvasSyncService.sync(
                snapshot,
                connection: connection,
                on: req.db
            )
            let durationMS = Int(Date().timeIntervalSince(startedAt) * 1_000)
            req.logger.info(
                "Canvas sync completed",
                metadata: [
                    "connection_id": "\(connectionID)",
                    "snapshot_id": "\(response.snapshotID)",
                    "course_count": "\(snapshot.courses.count)",
                    "assignment_count": "\(snapshot.courses.reduce(0) { $0 + $1.assignments.count })",
                    "duration_ms": "\(durationMS)",
                ]
            )
            return response
        } catch {
            let safeCode = (error as? AbortError).map { "http_\($0.status.code)" }
                ?? "internal_error"
            req.logger.warning(
                "Canvas sync failed",
                metadata: [
                    "connection_id": "\(connectionID)",
                    "safe_error_code": "\(safeCode)",
                ]
            )
            throw error
        }
    }
}
