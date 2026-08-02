import Crypto
import Foundation
import Vapor

enum TapTokenService {
    static let tokenPrefix = "fbt_"
    static let tokenByteCount = 24
    static let maximumURLByteCount = 504

    /// Creates 192 random bits and encodes them without Base64 padding. The
    /// prefix identifies the value as a Flowboard Tap bearer capability.
    static func generate() -> (raw: String, hash: String, visiblePrefix: String) {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<tokenByteCount).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        let encoded = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let raw = tokenPrefix + encoded
        return (raw, hash(raw), String(raw.prefix(12)))
    }

    static func hash(_ rawToken: String) -> String {
        SHA256.hash(data: Data(rawToken.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func isWellFormed(_ rawToken: String) -> Bool {
        guard rawToken.hasPrefix(tokenPrefix) else { return false }
        let payload = rawToken.dropFirst(tokenPrefix.count)
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        return payload.count == 32 && payload.allSatisfy {
            alphabet.contains($0)
        }
    }

    /// Joins the configured public Tap surface and token fragment. The byte
    /// limit applies to the complete UTF-8 URL that is written to an NFC tag.
    static func makeURL(rawToken: String, baseURL: String) throws -> String {
        let cleanBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            isWellFormed(rawToken),
            var components = URLComponents(string: cleanBaseURL),
            components.host != nil,
            components.scheme == "https" || components.scheme == "http",
            components.query == nil,
            components.fragment == nil
        else {
            throw Abort(.unprocessableEntity, reason: "Configure an absolute HTTP or HTTPS Tap URL without a query or fragment.")
        }
        components.fragment = rawToken
        guard let result = components.string else {
            throw Abort(.unprocessableEntity, reason: "The Tap URL could not be created.")
        }
        guard result.utf8.count < maximumURLByteCount else {
            throw Abort(.unprocessableEntity, reason: "The Tap URL must use fewer than 504 UTF-8 bytes.")
        }
        return result
    }

    /// `TAP_BASE_URL` is the public URL written to tags. Its default uses the
    /// current request origin and `/t`; a short Railway custom domain can replace it.
    static func makeURL(rawToken: String, for req: Request) throws -> String {
        let baseURL = Environment.get("TAP_BASE_URL") ?? defaultBaseURL(for: req)
        if req.application.environment == .production,
            URLComponents(string: baseURL)?.scheme != "https"
        {
            throw Abort(.unprocessableEntity, reason: "TAP_BASE_URL must use HTTPS in production.")
        }
        return try makeURL(rawToken: rawToken, baseURL: baseURL)
    }

    private static func defaultBaseURL(for req: Request) -> String {
        let scheme = req.headers.first(name: "X-Forwarded-Proto")?
            .split(separator: ",")
            .first
            .map(String.init)
            ?? (req.application.environment == .production ? "https" : "http")
        let host = req.headers.first(name: .host) ?? "localhost:8080"
        return "\(scheme)://\(host)/t"
    }
}
