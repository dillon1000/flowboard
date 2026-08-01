import Foundation

struct APIKeysPageContext: Encodable {
    let keys: [APIKeyPageItemContext]
    let hasKeys: Bool
    let apiBaseURL: String
    let createdKey: String
    let hasCreatedKey: Bool
    let error: String
    let hasError: Bool

    init(
        credentials: [APIKeyCredential],
        apiBaseURL: String,
        createdKey: String? = nil,
        error: String? = nil
    ) throws {
        self.keys = try credentials.map(APIKeyPageItemContext.init)
        self.hasKeys = !credentials.isEmpty
        self.apiBaseURL = apiBaseURL
        self.createdKey = createdKey ?? ""
        self.hasCreatedKey = createdKey != nil
        self.error = error ?? ""
        self.hasError = error != nil
    }
}

struct APIKeyPageItemContext: Encodable {
    let id: UUID
    let name: String
    let prefix: String
    let createdAt: String
    let expiresAt: String
    let lastUsedAt: String

    init(credential: APIKeyCredential) throws {
        self.id = try credential.requireID()
        self.name = credential.name
        self.prefix = credential.keyPrefix
        self.createdAt = credential.createdAt.map(apiKeyDisplayDate) ?? "Unknown"
        self.expiresAt = credential.expiresAt.map(apiKeyDisplayDate) ?? "Never"
        self.lastUsedAt = credential.lastUsedAt.map(apiKeyDisplayDateTime) ?? "Not used"
    }
}

private func apiKeyDisplayDate(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().year())
}

private func apiKeyDisplayDateTime(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
}
