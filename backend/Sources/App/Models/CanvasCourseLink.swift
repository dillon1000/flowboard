import Fluent
import Foundation

/// Connects one remote Canvas course to one user-owned Focalpoint board.
/// Canvas manages only the fields stored here and the academic fields copied to the board context.
final class CanvasCourseLink: Model, @unchecked Sendable {
    static let schema = "canvas_course_links"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "connection_id")
    var connection: CanvasConnection

    @Field(key: "remote_course_id")
    var remoteCourseID: String

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "canvas_course_url")
    var canvasCourseURL: String

    @OptionalField(key: "course_code")
    var courseCode: String?

    @OptionalField(key: "term_name")
    var termName: String?

    @OptionalField(key: "current_score")
    var currentScore: Double?

    @OptionalField(key: "current_grade")
    var currentGrade: String?

    @Field(key: "consecutive_missing_count")
    var consecutiveMissingCount: Int

    @Field(key: "sync_archived")
    var syncArchived: Bool

    @Children(for: \.$courseLink)
    var assignments: [CanvasAssignmentLink]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        connectionID: UUID,
        remoteCourseID: String,
        boardID: UUID,
        canvasCourseURL: String,
        courseCode: String? = nil,
        termName: String? = nil,
        currentScore: Double? = nil,
        currentGrade: String? = nil
    ) {
        self.id = id
        self.$connection.id = connectionID
        self.remoteCourseID = remoteCourseID
        self.$board.id = boardID
        self.canvasCourseURL = canvasCourseURL
        self.courseCode = courseCode
        self.termName = termName
        self.currentScore = currentScore
        self.currentGrade = currentGrade
        self.consecutiveMissingCount = 0
        self.syncArchived = false
    }
}
