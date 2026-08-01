import Crypto
import Fluent
import Foundation
import Vapor

enum APIKeyService {
    /// The prefix identifies Flowboard credentials in logs and secret scanners.
    /// Changing it affects only new keys because authentication hashes the full value.
    static let keyPrefix = "fbk_"

    /// Creates a high-entropy credential and its database-safe identity values.
    /// The caller must return the raw value once and must never persist it.
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

    /// Validates and creates one credential. The returned raw value exists only
    /// in memory, and callers must show it once without logging or persisting it.
    static func create(
        name: String,
        expiresAt: Date?,
        userID: UUID,
        on database: any Database
    ) async throws -> (credential: APIKeyCredential, raw: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(cleanName.count) else {
            throw Abort(.unprocessableEntity, reason: "API key name must contain 1 to 80 characters.")
        }
        if let expiresAt, expiresAt <= Date() {
            throw Abort(.unprocessableEntity, reason: "API key expiry must be in the future.")
        }

        let generated = generate()
        let credential = APIKeyCredential(
            userID: userID,
            name: cleanName,
            keyHash: generated.hash,
            keyPrefix: generated.visiblePrefix,
            expiresAt: expiresAt
        )
        try await credential.create(on: database)
        return (credential, generated.raw)
    }

    /// Finds a usable key and its owner. Expired and unknown values have the same
    /// result so an authentication response does not disclose key state.
    static func authenticate(
        _ rawKey: String,
        on database: any Database
    ) async throws -> APIKeyCredential? {
        guard rawKey.hasPrefix(keyPrefix) else {
            return nil
        }
        guard let credential = try await APIKeyCredential.query(on: database)
            .filter(\.$keyHash == hash(rawKey))
            .with(\.$user)
            .first()
        else {
            return nil
        }
        if let expiresAt = credential.expiresAt, expiresAt <= Date() {
            return nil
        }
        return credential
    }

    private static func hex(_ byte: UInt8) -> String {
        String(format: "%02x", byte)
    }
}
