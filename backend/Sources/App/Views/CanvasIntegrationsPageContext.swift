import Foundation

struct CanvasIntegrationsPageContext: Encodable {
    let connections: [CanvasIntegrationConnectionContext]
    let hasConnections: Bool
    let focalpointOrigin: String

    init(connections: [CanvasConnection], focalpointOrigin: String) throws {
        self.connections = try connections.map(CanvasIntegrationConnectionContext.init)
        self.hasConnections = !connections.isEmpty
        self.focalpointOrigin = focalpointOrigin
    }
}

struct CanvasIntegrationConnectionContext: Encodable {
    let id: UUID
    let canvasOrigin: String
    let keyPrefix: String
    let lastSyncDisplay: String
    let statusName: String
    let statusDetail: String
    let hasError: Bool

    init(connection: CanvasConnection) throws {
        self.id = try connection.requireID()
        self.canvasOrigin = connection.canvasOrigin
        self.keyPrefix = connection.syncKeyPrefix
        self.lastSyncDisplay = connection.lastSuccessfulSyncAt.map(displayDate) ?? "Never"
        self.hasError = connection.lastErrorSummary != nil
        self.statusName = hasError ? "Needs attention" : connection.lastSuccessfulSyncAt == nil ? "Ready" : "Connected"
        self.statusDetail = connection.lastErrorSummary ?? "The extension can send a complete Canvas snapshot."
    }
}
