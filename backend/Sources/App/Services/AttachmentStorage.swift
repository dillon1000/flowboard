import Foundation
import SotoSignerV4
import Vapor

/// Owns the private S3-compatible client used for attachment objects.
///
/// Production requires all Railway bucket variables. Development and tests keep
/// the existing local file backend so contributors do not need shared credentials.
final class AttachmentStorage: Sendable {
    private let remote: RemoteConfiguration?

    var usesRemoteStore: Bool {
        remote != nil
    }

    private init(remote: RemoteConfiguration?) {
        self.remote = remote
    }

    /// Builds one storage client from Railway's S3-compatible environment variables.
    ///
    /// Partial configuration fails at startup. This prevents production uploads from
    /// silently returning to the container volume when a credential is missing.
    static func configured(for environment: Environment) throws -> AttachmentStorage {
        let variableNames = [
            "AWS_ENDPOINT_URL",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_S3_BUCKET_NAME",
            "AWS_DEFAULT_REGION",
            "AWS_S3_URL_STYLE",
        ]
        let values = Dictionary(
            uniqueKeysWithValues: variableNames.compactMap { name in
                Environment.get(name).map { (name, $0) }
            }
        )

        let bucketConfigurationStarted = [
            "AWS_ENDPOINT_URL",
            "AWS_S3_BUCKET_NAME",
            "AWS_S3_URL_STYLE",
        ].contains { values[$0] != nil }
        if !bucketConfigurationStarted {
            guard environment != .production else {
                throw AttachmentStorageError.missingConfiguration(variableNames)
            }
            return AttachmentStorage(remote: nil)
        }

        let missingNames = variableNames.filter { values[$0] == nil }
        guard missingNames.isEmpty else {
            throw AttachmentStorageError.missingConfiguration(missingNames)
        }
        guard
            let endpoint = values["AWS_ENDPOINT_URL"],
            let endpointURL = URL(string: endpoint),
            endpointURL.scheme == "https",
            endpointURL.host != nil
        else {
            throw AttachmentStorageError.invalidEndpoint
        }
        guard
            let bucket = values["AWS_S3_BUCKET_NAME"],
            let region = values["AWS_DEFAULT_REGION"],
            let urlStyleValue = values["AWS_S3_URL_STYLE"],
            let accessKeyID = values["AWS_ACCESS_KEY_ID"],
            let secretAccessKey = values["AWS_SECRET_ACCESS_KEY"]
        else {
            throw AttachmentStorageError.missingConfiguration(variableNames)
        }

        let urlStyle: URLStyle
        switch urlStyleValue {
        case "path", "path-style":
            urlStyle = .path
        case "virtual", "virtual-host", "virtual-hosted":
            urlStyle = .virtualHost
        default:
            throw AttachmentStorageError.invalidURLStyle(urlStyleValue)
        }

        // Railway supplies static bucket credentials. Soto signs the three S3
        // requests, and Vapor's existing HTTP client sends them.
        let signer = AWSSigner(
            credentials: StaticCredential(
                accessKeyId: accessKeyID,
                secretAccessKey: secretAccessKey
            ),
            name: "s3",
            region: region
        )
        return AttachmentStorage(
            remote: RemoteConfiguration(
                endpoint: endpointURL,
                bucket: bucket,
                urlStyle: urlStyle,
                signer: signer
            )
        )
    }

    /// Creates the stable object key stored in the existing `storage_name` field.
    ///
    /// The prefix distinguishes new bucket objects from legacy attachment rows,
    /// which contain only a generated file name and remain readable from `/data`.
    static func objectKey(
        boardID: UUID,
        taskID: UUID,
        storageName: String
    ) -> String {
        "attachments/\(boardID.uuidString)/\(taskID.uuidString)/\(storageName)"
    }

    /// Returns true only for keys produced by `objectKey`.
    static func isObjectKey(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 4
            && parts[0] == "attachments"
            && UUID(uuidString: String(parts[1])) != nil
            && UUID(uuidString: String(parts[2])) != nil
            && !parts[3].isEmpty
            && parts[3] != "."
            && parts[3] != ".."
    }

    /// Uploads one complete attachment. Callers persist its database row only after
    /// this operation succeeds, and delete the object if that database write fails.
    func put(
        data: Data,
        key: String,
        contentType: String,
        using client: any Client
    ) async throws {
        let remote = try remoteStore()
        let url = try remote.objectURL(key: key)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentLength, value: String(data.count))
        headers.replaceOrAdd(name: .contentType, value: contentType)
        headers = remote.signer.signHeaders(
            url: url,
            method: .PUT,
            headers: headers,
            body: .data(data)
        )
        let response = try await client.send(
            .PUT,
            headers: headers,
            to: URI(string: url.absoluteString)
        ) { request in
            request.body = ByteBuffer(bytes: data)
        }
        try validate(response)
    }

    /// Downloads a complete object. Attachments are capped at 10 MB during upload,
    /// so buffering the body preserves the current Vapor response behavior safely.
    func get(key: String, using client: any Client) async throws -> Data {
        let remote = try remoteStore()
        let url = try remote.objectURL(key: key)
        let headers = remote.signer.signHeaders(
            url: url,
            method: .GET
        )
        let response = try await client.get(
            URI(string: url.absoluteString),
            headers: headers
        )
        try validate(response)
        guard let buffer = response.body else {
            return Data()
        }
        guard
            buffer.readableBytes <= 10_000_000,
            let data = buffer.getData(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            )
        else {
            throw AttachmentStorageError.missingObjectBody
        }
        return data
    }

    /// Removes one object. S3 delete is idempotent, so callers can safely retry a
    /// task or board deletion after a transient storage failure.
    func delete(key: String, using client: any Client) async throws {
        let remote = try remoteStore()
        let url = try remote.objectURL(key: key)
        let headers = remote.signer.signHeaders(
            url: url,
            method: .DELETE
        )
        let response = try await client.delete(
            URI(string: url.absoluteString),
            headers: headers
        )
        try validate(response)
    }

    private func remoteStore() throws -> RemoteConfiguration {
        guard let remote else {
            throw AttachmentStorageError.remoteStoreUnavailable
        }
        return remote
    }

    private func validate(_ response: ClientResponse) throws {
        guard (200..<300).contains(response.status.code) else {
            throw AttachmentStorageError.requestFailed(response.status.code)
        }
    }
}

private struct RemoteConfiguration: Sendable {
    let endpoint: URL
    let bucket: String
    let urlStyle: URLStyle
    let signer: AWSSigner

    /// Builds and normalizes the request URL before signing it. Object keys are
    /// generated by the server, so user-provided file names never enter the path.
    func objectURL(key: String) throws -> URL {
        guard
            AttachmentStorage.isObjectKey(key),
            var components = URLComponents(
                url: endpoint,
                resolvingAgainstBaseURL: false
            ),
            let host = components.host
        else {
            throw AttachmentStorageError.invalidObjectKey
        }

        let basePath = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        switch urlStyle {
        case .path:
            components.path = "/"
                + [basePath, bucket, key].filter { !$0.isEmpty }.joined(separator: "/")
        case .virtualHost:
            components.host = "\(bucket).\(host)"
            components.path = "/"
                + [basePath, key].filter { !$0.isEmpty }.joined(separator: "/")
        }
        guard
            let url = components.url,
            let signedURL = signer.processURL(url: url)
        else {
            throw AttachmentStorageError.invalidObjectKey
        }
        return signedURL
    }
}

private enum URLStyle: Sendable {
    case path
    case virtualHost
}

private enum AttachmentStorageError: Error, CustomStringConvertible {
    case invalidEndpoint
    case invalidObjectKey
    case invalidURLStyle(String)
    case missingConfiguration([String])
    case missingObjectBody
    case requestFailed(UInt)
    case remoteStoreUnavailable

    var description: String {
        switch self {
        case .invalidEndpoint:
            "AWS_ENDPOINT_URL must be a valid HTTPS endpoint."
        case .invalidObjectKey:
            "The attachment object key is invalid."
        case let .invalidURLStyle(value):
            "AWS_S3_URL_STYLE has unsupported value '\(value)'."
        case let .missingConfiguration(names):
            "Attachment storage is missing: \(names.joined(separator: ", "))."
        case .missingObjectBody:
            "The attachment object has no response body."
        case let .requestFailed(status):
            "Attachment storage returned HTTP \(status)."
        case .remoteStoreUnavailable:
            "Remote attachment storage is not configured."
        }
    }
}

private struct AttachmentStorageKey: StorageKey {
    typealias Value = AttachmentStorage
}

extension Application {
    var attachmentStorage: AttachmentStorage {
        get {
            guard let storage = self.storage[AttachmentStorageKey.self] else {
                fatalError("Attachment storage was used before configuration.")
            }
            return storage
        }
        set {
            self.storage[AttachmentStorageKey.self] = newValue
        }
    }
}
