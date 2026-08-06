import Fluent

/// Creates the private Canvas connection and link tables. Deleting a connection
/// removes its links, while linked boards and tasks remain independent records.
struct CreateCanvasSyncModels: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(CanvasConnection.schema)
            .id()
            .field(
                "user_id",
                .uuid,
                .required,
                .references(User.schema, "id", onDelete: .cascade)
            )
            .field("canvas_origin", .string, .required)
            .field("sync_key_hash", .string, .required)
            .field("sync_key_prefix", .string, .required)
            .field("last_snapshot_id", .string)
            .field("last_captured_at", .datetime)
            .field("last_successful_sync_at", .datetime)
            .field("last_error_summary", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "canvas_origin")
            .unique(on: "sync_key_hash")
            .create()

        try await database.schema(CanvasCourseLink.schema)
            .id()
            .field(
                "connection_id",
                .uuid,
                .required,
                .references(CanvasConnection.schema, "id", onDelete: .cascade)
            )
            .field("remote_course_id", .string, .required)
            .field(
                "board_id",
                .uuid,
                .required,
                .references(Board.schema, "id", onDelete: .restrict)
            )
            .field("canvas_course_url", .string, .required)
            .field("course_code", .string)
            .field("term_name", .string)
            .field("current_score", .double)
            .field("current_grade", .string)
            .field("consecutive_missing_count", .int, .required, .sql(.default(0)))
            .field("sync_archived", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "connection_id", "remote_course_id")
            .unique(on: "board_id")
            .create()

        try await database.schema(CanvasAssignmentLink.schema)
            .id()
            .field(
                "course_link_id",
                .uuid,
                .required,
                .references(CanvasCourseLink.schema, "id", onDelete: .cascade)
            )
            .field("remote_assignment_id", .string, .required)
            .field(
                "task_id",
                .uuid,
                .required,
                .references(Task.schema, "id", onDelete: .restrict)
            )
            .field("canvas_assignment_url", .string, .required)
            .field("submission_state", .string)
            .field("grade_label", .string)
            .field("submitted_at", .datetime)
            .field("is_late", .bool, .required, .sql(.default(false)))
            .field("is_missing", .bool, .required, .sql(.default(false)))
            .field("is_excused", .bool, .required, .sql(.default(false)))
            .field("redo_requested", .bool, .required, .sql(.default(false)))
            .field("consecutive_missing_count", .int, .required, .sql(.default(0)))
            .field("sync_archived", .bool, .required, .sql(.default(false)))
            .field("status_before_canvas_completion", .string)
            .field("canvas_controls_completion", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "course_link_id", "remote_assignment_id")
            .unique(on: "task_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(CanvasAssignmentLink.schema).delete()
        try await database.schema(CanvasCourseLink.schema).delete()
        try await database.schema(CanvasConnection.schema).delete()
    }
}
