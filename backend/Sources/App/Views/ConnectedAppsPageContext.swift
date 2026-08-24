import Foundation

struct ConnectedAppsPageContext: Encodable {
    let connections: [ConnectedAppPageItemContext]
    let hasConnections: Bool
    let mcpServerURL: String

    init(tokens: [MCPOAuthToken], mcpServerURL: String) throws {
        let grouped = Dictionary(grouping: tokens, by: \.$client.id)
        self.connections = try grouped.values.map { clientTokens in
            guard let first = clientTokens.first else {
                throw CocoaError(.coderInvalidValue)
            }
            let latest = clientTokens.compactMap(\.updatedAt).max()
                ?? clientTokens.compactMap(\.createdAt).max()
            return ConnectedAppPageItemContext(
                id: try first.client.requireID(),
                name: first.client.clientName,
                scope: "Read workspace data",
                connectedAt: latest.map(connectedAppDisplayDate) ?? "Unknown"
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.hasConnections = !connections.isEmpty
        self.mcpServerURL = mcpServerURL
    }
}

struct ConnectedAppPageItemContext: Encodable {
    let id: UUID
    let name: String
    let scope: String
    let connectedAt: String
}

private func connectedAppDisplayDate(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
}
