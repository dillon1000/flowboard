import Fluent
import Foundation

/// Maps one provider identity to a Flowboard user. A separate model keeps the
/// user record independent from provider details and permits more providers later.
final class OAuthAccount: Model, @unchecked Sendable {
    static let schema = "oauth_accounts"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "provider_id")
    var providerID: String

    @Field(key: "provider_user_id")
    var providerUserID: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        providerID: String,
        providerUserID: String
    ) {
        self.id = id
        self.$user.id = userID
        self.providerID = providerID
        self.providerUserID = providerUserID
    }
}
