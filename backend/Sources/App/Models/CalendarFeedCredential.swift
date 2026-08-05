import Fluent
import Foundation
import Vapor

/// Stores only the digest of a calendar subscription token. The raw token is
/// returned once when the user creates or rotates the feed.
final class CalendarFeedCredential: Model, @unchecked Sendable {
    static let schema = "calendar_feed_credentials"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "token_prefix")
    var tokenPrefix: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: UUID, tokenHash: String, tokenPrefix: String) {
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.tokenPrefix = tokenPrefix
    }
}

struct CalendarFeedStatusResponse: Content {
    let isEnabled: Bool
    let prefix: String
    let createdAt: Date?
    let updatedAt: Date?

    init(credential: CalendarFeedCredential?) {
        self.isEnabled = credential != nil
        self.prefix = credential?.tokenPrefix ?? ""
        self.createdAt = credential?.createdAt
        self.updatedAt = credential?.updatedAt
    }
}

struct CreatedCalendarFeedResponse: Content {
    let token: String
    let prefix: String
}
