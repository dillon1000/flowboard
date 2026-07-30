import Foundation
import Vapor

extension HTTPHeaders.Name {
    static let flowboardServerName = Self("X-Server-Name")
    static let flowboardServerTime = Self("X-Server-Time")
    static let flowboardServerVersion = Self("X-Server-Version")
}

/// Adds server identity and response time metadata to every HTTP response.
/// The configured name and version stay stable for one process, while the time
/// records when the server finishes each request.
struct ServerHeadersMiddleware: AsyncMiddleware {
    let serverName: String
    let serverVersion: String

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: .flowboardServerName, value: serverName)
        response.headers.replaceOrAdd(name: .flowboardServerTime, value: Date().ISO8601Format())
        response.headers.replaceOrAdd(name: .flowboardServerVersion, value: serverVersion)
        return response
    }
}
