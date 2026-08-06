import Fluent
import Foundation
import Vapor

/// Stores one Canvas origin and its restricted sync credential for one user.
/// The raw credential never enters this model or the database.
final class CanvasConnection: Model, @unchecked Sendable {
    static let schema = "canvas_connections"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "canvas_origin")
    var canvasOrigin: String

    @Field(key: "sync_key_hash")
    var syncKeyHash: String

    @Field(key: "sync_key_prefix")
    var syncKeyPrefix: String

    @OptionalField(key: "last_snapshot_id")
    var lastSnapshotID: String?

    @OptionalField(key: "last_captured_at")
    var lastCapturedAt: Date?

    @OptionalField(key: "last_successful_sync_at")
    var lastSuccessfulSyncAt: Date?

    /// Contains a user-safe code and summary. It must not contain Canvas data or secrets.
    @OptionalField(key: "last_error_summary")
    var lastErrorSummary: String?

    @Children(for: \.$connection)
    var courses: [CanvasCourseLink]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        canvasOrigin: String,
        syncKeyHash: String,
        syncKeyPrefix: String
    ) {
        self.id = id
        self.$user.id = userID
        self.canvasOrigin = canvasOrigin
        self.syncKeyHash = syncKeyHash
        self.syncKeyPrefix = syncKeyPrefix
    }
}

extension CanvasConnection: Authenticatable {}

struct CreateCanvasConnectionRequest: Content {
    let canvasOrigin: String
}

struct CanvasConnectionResponse: Content {
    let id: UUID
    let canvasOrigin: String
    let keyPrefix: String
    let lastSnapshotID: String?
    let lastCapturedAt: Date?
    let lastSuccessfulSyncAt: Date?
    let lastErrorSummary: String?
    let createdAt: Date?
    let updatedAt: Date?

    init(connection: CanvasConnection) throws {
        self.id = try connection.requireID()
        self.canvasOrigin = connection.canvasOrigin
        self.keyPrefix = connection.syncKeyPrefix
        self.lastSnapshotID = connection.lastSnapshotID
        self.lastCapturedAt = connection.lastCapturedAt
        self.lastSuccessfulSyncAt = connection.lastSuccessfulSyncAt
        self.lastErrorSummary = connection.lastErrorSummary
        self.createdAt = connection.createdAt
        self.updatedAt = connection.updatedAt
    }
}

/// Returns a new raw sync key once. List and status responses expose only its prefix.
struct CreatedCanvasConnectionResponse: Content {
    let connection: CanvasConnectionResponse
    let syncKey: String

    init(connection: CanvasConnection, syncKey: String) throws {
        self.connection = try CanvasConnectionResponse(connection: connection)
        self.syncKey = syncKey
    }
}
