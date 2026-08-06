import Crypto
import Fluent
import Foundation
import Vapor

enum CanvasCredentialService {
    /// This prefix distinguishes the narrow Canvas credential from general API keys.
    static let keyPrefix = "fcs_"

    /// Creates 256 bits of random key material. Only the digest and visible prefix persist.
    static func generate() -> (raw: String, hash: String, visiblePrefix: String) {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        let raw = keyPrefix + bytes.map(hex).joined()
        return (raw, hash(raw), String(raw.prefix(12)))
    }

    static func hash(_ rawKey: String) -> String {
        SHA256.hash(data: Data(rawKey.utf8)).map(hex).joined()
    }

    /// Converts one HTTPS origin-only value into its stable lowercase host form.
    /// Canvas paths, credentials, queries, and fragments are rejected.
    static func canonicalOrigin(_ suppliedValue: String) throws -> String {
        let value = suppliedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else {
            throw Abort(
                .unprocessableEntity,
                reason: "Canvas origin must be an HTTPS origin without a path, credentials, query, or fragment."
            )
        }
        components.scheme = "https"
        components.host = host
        components.path = ""
        guard let origin = components.string, origin.count <= 2_048 else {
            throw Abort(.unprocessableEntity, reason: "Canvas origin is too long.")
        }
        return origin
    }

    static func create(
        canvasOrigin: String,
        userID: UUID,
        on database: any Database
    ) async throws -> (connection: CanvasConnection, raw: String) {
        let origin = try canonicalOrigin(canvasOrigin)
        let exists = try await CanvasConnection.query(on: database)
            .filter(\.$user.$id == userID)
            .filter(\.$canvasOrigin == origin)
            .first() != nil
        guard !exists else {
            throw Abort(.conflict, reason: "This Canvas origin is already connected.")
        }
        let generated = generate()
        let connection = CanvasConnection(
            userID: userID,
            canvasOrigin: origin,
            syncKeyHash: generated.hash,
            syncKeyPrefix: generated.visiblePrefix
        )
        try await connection.create(on: database)
        return (connection, generated.raw)
    }

    static func rotate(
        connection: CanvasConnection,
        on database: any Database
    ) async throws -> String {
        let generated = generate()
        connection.syncKeyHash = generated.hash
        connection.syncKeyPrefix = generated.visiblePrefix
        try await connection.update(on: database)
        return generated.raw
    }

    /// Unknown and malformed credentials have the same result so key state is private.
    static func authenticate(
        _ rawKey: String,
        on database: any Database
    ) async throws -> CanvasConnection? {
        guard rawKey.hasPrefix(keyPrefix) else { return nil }
        return try await CanvasConnection.query(on: database)
            .filter(\.$syncKeyHash == hash(rawKey))
            .first()
    }

    private static func hex(_ byte: UInt8) -> String {
        String(format: "%02x", byte)
    }
}
