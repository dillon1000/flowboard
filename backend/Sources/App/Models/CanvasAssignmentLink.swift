import Fluent
import Foundation

/// Connects one Canvas assignment to one Focalpoint task and records source state.
/// Planning and collaboration fields remain on the task and are never copied here.
final class CanvasAssignmentLink: Model, @unchecked Sendable {
    static let schema = "canvas_assignment_links"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "course_link_id")
    var courseLink: CanvasCourseLink

    @Field(key: "remote_assignment_id")
    var remoteAssignmentID: String

    @Parent(key: "task_id")
    var task: Task

    @Field(key: "canvas_assignment_url")
    var canvasAssignmentURL: String

    @OptionalField(key: "submission_state")
    var submissionState: String?

    @OptionalField(key: "grade_label")
    var gradeLabel: String?

    @OptionalField(key: "submitted_at")
    var submittedAt: Date?

    @Field(key: "is_late")
    var isLate: Bool

    @Field(key: "is_missing")
    var isMissing: Bool

    @Field(key: "is_excused")
    var isExcused: Bool

    @Field(key: "redo_requested")
    var redoRequested: Bool

    @Field(key: "consecutive_missing_count")
    var consecutiveMissingCount: Int

    @Field(key: "sync_archived")
    var syncArchived: Bool

    @OptionalField(key: "status_before_canvas_completion")
    var statusBeforeCanvasCompletion: String?

    @Field(key: "canvas_controls_completion")
    var canvasControlsCompletion: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        courseLinkID: UUID,
        remoteAssignmentID: String,
        taskID: UUID,
        canvasAssignmentURL: String
    ) {
        self.id = id
        self.$courseLink.id = courseLinkID
        self.remoteAssignmentID = remoteAssignmentID
        self.$task.id = taskID
        self.canvasAssignmentURL = canvasAssignmentURL
        self.isLate = false
        self.isMissing = false
        self.isExcused = false
        self.redoRequested = false
        self.consecutiveMissingCount = 0
        self.syncArchived = false
        self.canvasControlsCompletion = false
    }
}
