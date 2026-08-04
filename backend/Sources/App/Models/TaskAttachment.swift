import Fluent
import Vapor

/// Maps file extensions to media types that browsers can render without active
/// document content. SVG and other executable formats remain download-only.
struct AttachmentPreview {
    enum Kind {
        case image
        case audio
        case video
    }

    let kind: Kind
    let mediaType: HTTPMediaType

    init?(fileName: String) {
        guard fileName.contains("."),
              let fileExtension = fileName.split(separator: ".").last?.lowercased()
        else {
            return nil
        }

        switch fileExtension {
        case "avif":
            self.init(kind: .image, mediaType: .avif)
        case "gif":
            self.init(kind: .image, mediaType: .gif)
        case "heic":
            self.init(kind: .image, mediaType: .heic)
        case "jpg", "jpeg":
            self.init(kind: .image, mediaType: .jpeg)
        case "png":
            self.init(kind: .image, mediaType: .png)
        case "webp":
            self.init(kind: .image, mediaType: .webp)
        case "aac":
            self.init(kind: .audio, mediaType: .init(type: "audio", subType: "aac"))
        case "flac":
            self.init(kind: .audio, mediaType: .init(type: "audio", subType: "flac"))
        case "m4a":
            self.init(kind: .audio, mediaType: .init(type: "audio", subType: "mp4"))
        case "mp3":
            self.init(kind: .audio, mediaType: .mp3)
        case "ogg":
            self.init(kind: .audio, mediaType: .init(type: "audio", subType: "ogg"))
        case "wav":
            self.init(kind: .audio, mediaType: .wave)
        case "m4v":
            self.init(kind: .video, mediaType: .init(type: "video", subType: "x-m4v"))
        case "mov":
            self.init(kind: .video, mediaType: .init(type: "video", subType: "quicktime"))
        case "mp4":
            self.init(kind: .video, mediaType: .init(type: "video", subType: "mp4"))
        case "ogv":
            self.init(kind: .video, mediaType: .init(type: "video", subType: "ogg"))
        case "webm":
            self.init(kind: .video, mediaType: .init(type: "video", subType: "webm"))
        default:
            return nil
        }
    }

    private init(kind: Kind, mediaType: HTTPMediaType) {
        self.kind = kind
        self.mediaType = mediaType
    }
}

final class TaskAttachment: Model, @unchecked Sendable {
    static let schema = "task_attachments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: Task

    @Parent(key: "uploaded_by_id")
    var uploadedBy: User

    @Field(key: "file_name")
    var fileName: String

    /// Stores the full server-generated `attachments/...` object key.
    @Field(key: "storage_name")
    var storageName: String

    @Field(key: "content_type")
    var contentType: String

    @Field(key: "byte_count")
    var byteCount: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        taskID: UUID,
        uploadedByID: UUID,
        fileName: String,
        storageName: String,
        contentType: String,
        byteCount: Int
    ) {
        self.id = id
        self.$task.id = taskID
        self.$uploadedBy.id = uploadedByID
        self.fileName = fileName
        self.storageName = storageName
        self.contentType = contentType
        self.byteCount = byteCount
    }

    var preview: AttachmentPreview? {
        AttachmentPreview(fileName: fileName)
    }
}
