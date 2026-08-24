import Fluent

struct CreateMCPOAuthModels: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MCPOAuthClient.schema)
            .id()
            .field("client_id", .string, .required)
            .field("client_name", .string, .required)
            .field("redirect_uris", .json, .required)
            .field("created_at", .datetime)
            .unique(on: "client_id")
            .create()

        try await database.schema(MCPOAuthAuthorizationCode.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field(
                "client_id",
                .uuid,
                .required,
                .references(MCPOAuthClient.schema, "id", onDelete: .cascade)
            )
            .field("code_hash", .string, .required)
            .field("redirect_uri", .string, .required)
            .field("code_challenge", .string, .required)
            .field("scope", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .unique(on: "code_hash")
            .create()

        try await database.schema(MCPOAuthToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field(
                "client_id",
                .uuid,
                .required,
                .references(MCPOAuthClient.schema, "id", onDelete: .cascade)
            )
            .field("access_token_hash", .string, .required)
            .field("refresh_token_hash", .string, .required)
            .field("scope", .string, .required)
            .field("access_token_expires_at", .datetime, .required)
            .field("refresh_token_expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "access_token_hash")
            .unique(on: "refresh_token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(MCPOAuthToken.schema).delete()
        try await database.schema(MCPOAuthAuthorizationCode.schema).delete()
        try await database.schema(MCPOAuthClient.schema).delete()
    }
}
