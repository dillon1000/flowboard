import Foundation
import Vapor

/// Encodes internal page-data models with a stable JSON date format.
/// Encoding failures propagate to Vapor's error middleware without sending a partial body.
func jsonResponse<Value: Encodable>(
    _ value: Value,
    status: HTTPResponseStatus = .ok
) throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let response = Response(status: status, body: .init(data: try encoder.encode(value)))
    response.headers.contentType = .json
    return response
}
