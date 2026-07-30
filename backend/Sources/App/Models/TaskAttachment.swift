import Fluent
import Vapor

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
}
