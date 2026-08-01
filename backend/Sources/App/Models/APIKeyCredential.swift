import Fluent
import Foundation
import Vapor

/// Stores the identity and lifecycle data for one API key. `keyHash` is a
/// one-way digest, and `keyPrefix` lets a user identify a key after creation.
final class APIKeyCredential: Model, @unchecked Sendable {
    static let schema = "api_keys"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "name")
    var name: String

    @Field(key: "key_hash")
    var keyHash: String

    @Field(key: "key_prefix")
    var keyPrefix: String

    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    @OptionalField(key: "last_used_at")
    var lastUsedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        name: String,
        keyHash: String,
        keyPrefix: String,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.name = name
        self.keyHash = keyHash
        self.keyPrefix = keyPrefix
        self.expiresAt = expiresAt
    }
}

struct CreateAPIKeyRequest: Content, Validatable {
    let name: String
    let expiresAt: Date?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(1...80))
    }
}

struct APIKeyResponse: Content {
    let id: UUID
    let name: String
    let prefix: String
    let expiresAt: Date?
    let lastUsedAt: Date?
    let createdAt: Date?

    init(credential: APIKeyCredential) throws {
        self.id = try credential.requireID()
        self.name = credential.name
        self.prefix = credential.keyPrefix
        self.expiresAt = credential.expiresAt
        self.lastUsedAt = credential.lastUsedAt
        self.createdAt = credential.createdAt
    }
}

/// Returns the raw key only from the create operation. Later reads return
/// `APIKeyResponse`, which cannot disclose or reconstruct the credential.
struct CreatedAPIKeyResponse: Content {
    let id: UUID
    let name: String
    let prefix: String
    let key: String
    let expiresAt: Date?
    let createdAt: Date?

    init(credential: APIKeyCredential, key: String) throws {
        self.id = try credential.requireID()
        self.name = credential.name
        self.prefix = credential.keyPrefix
        self.key = key
        self.expiresAt = credential.expiresAt
        self.createdAt = credential.createdAt
    }
}
