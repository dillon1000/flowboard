import Foundation
import Vapor

struct CanvasSyncSnapshotV1: Content, Sendable {
    let version: Int
    let snapshotID: String
    let canvasOrigin: String
    let capturedAt: Date
    let courses: [CanvasCourseSnapshot]

    /// Validates the complete payload before a transaction can write local data.
    func validate(expectedOrigin: String) throws {
        guard version == 1 else {
            throw Abort(.unprocessableEntity, reason: "Unsupported Canvas snapshot version.")
        }
        try validateRequired(snapshotID, name: "Snapshot ID", maximum: 128)
        let canonicalOrigin = try CanvasCredentialService.canonicalOrigin(canvasOrigin)
        guard canonicalOrigin == expectedOrigin else {
            throw Abort(.forbidden, reason: "Canvas snapshot origin does not match this connection.")
        }
        guard courses.count <= 100 else {
            throw Abort(.payloadTooLarge, reason: "A Canvas snapshot can contain at most 100 courses.")
        }
        let assignmentCount = courses.reduce(0) { $0 + $1.assignments.count }
        guard assignmentCount <= 10_000 else {
            throw Abort(.payloadTooLarge, reason: "A Canvas snapshot can contain at most 10,000 assignments.")
        }

        var courseIDs: Set<String> = []
        for course in courses {
            try course.validate(canvasOrigin: canonicalOrigin)
            guard courseIDs.insert(course.id).inserted else {
                throw Abort(.unprocessableEntity, reason: "Canvas course IDs must be unique.")
            }
        }
    }
}

struct CanvasCourseSnapshot: Content, Sendable {
    let id: String
    let name: String
    let courseCode: String?
    let termName: String?
    let htmlURL: String
    let currentScore: Double?
    let currentGrade: String?
    let assignments: [CanvasAssignmentSnapshot]

    func validate(canvasOrigin: String) throws {
        try validateRequired(id, name: "Course ID", maximum: 255)
        try validateRequired(name, name: "Course name", maximum: 500)
        try validateOptional(courseCode, name: "Course code", maximum: 255)
        try validateOptional(termName, name: "Term name", maximum: 255)
        try validateCanvasURL(htmlURL, name: "Course URL", canvasOrigin: canvasOrigin)
        try validateFinite(currentScore, name: "Current score")
        try validateOptional(currentGrade, name: "Current grade", maximum: 255)

        var assignmentIDs: Set<String> = []
        for assignment in assignments {
            try assignment.validate(canvasOrigin: canvasOrigin)
            guard assignmentIDs.insert(assignment.id).inserted else {
                throw Abort(.unprocessableEntity, reason: "Canvas assignment IDs must be unique within a course.")
            }
        }
    }
}

struct CanvasAssignmentSnapshot: Content, Sendable {
    let id: String
    let name: String
    let descriptionText: String?
    let htmlURL: String
    let dueAt: Date?
    let pointsPossible: Double?
    let submission: CanvasSubmissionSnapshot?

    func validate(canvasOrigin: String) throws {
        try validateRequired(id, name: "Assignment ID", maximum: 255)
        try validateRequired(name, name: "Assignment name", maximum: 500)
        try validateOptional(descriptionText, name: "Assignment description", maximum: 5_000)
        try validateCanvasURL(htmlURL, name: "Assignment URL", canvasOrigin: canvasOrigin)
        try validateFinite(pointsPossible, name: "Points possible")
        if let pointsPossible, pointsPossible < 0 {
            throw Abort(.unprocessableEntity, reason: "Points possible cannot be negative.")
        }
        try submission?.validate()
    }
}

struct CanvasSubmissionSnapshot: Content, Sendable {
    let workflowState: String?
    let grade: String?
    let score: Double?
    let submittedAt: Date?
    let late: Bool
    let missing: Bool
    let excused: Bool
    let redoRequested: Bool

    func validate() throws {
        try validateOptional(workflowState, name: "Submission state", maximum: 100)
        try validateOptional(grade, name: "Grade label", maximum: 255)
        try validateFinite(score, name: "Submission score")
    }
}

private func validateRequired(_ value: String, name: String, maximum: Int) throws {
    let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanValue.isEmpty, value.count <= maximum else {
        throw Abort(.unprocessableEntity, reason: "\(name) must contain 1 to \(maximum) characters.")
    }
}

private func validateOptional(_ value: String?, name: String, maximum: Int) throws {
    guard let value else { return }
    guard value.count <= maximum else {
        throw Abort(.unprocessableEntity, reason: "\(name) cannot exceed \(maximum) characters.")
    }
}

private func validateFinite(_ value: Double?, name: String) throws {
    guard let value else { return }
    guard value.isFinite else {
        throw Abort(.unprocessableEntity, reason: "\(name) must be finite.")
    }
}

private func validateCanvasURL(_ value: String, name: String, canvasOrigin: String) throws {
    guard
        value.count <= 2_048,
        let components = URLComponents(string: value),
        components.scheme?.lowercased() == "https",
        let host = components.host?.lowercased(),
        !host.isEmpty,
        components.user == nil,
        components.password == nil
    else {
        throw Abort(.unprocessableEntity, reason: "\(name) must be a valid HTTPS URL.")
    }
    var originComponents = components
    originComponents.scheme = "https"
    originComponents.host = host
    originComponents.path = ""
    originComponents.query = nil
    originComponents.fragment = nil
    guard originComponents.string == canvasOrigin else {
        throw Abort(.unprocessableEntity, reason: "\(name) must use the connected Canvas origin.")
    }
}

struct CanvasSyncCounts: Content, Sendable {
    var coursesCreated = 0
    var coursesUpdated = 0
    var coursesArchived = 0
    var assignmentsCreated = 0
    var assignmentsUpdated = 0
    var assignmentsArchived = 0
    var assignmentsCompleted = 0
    var assignmentsReopened = 0
}

struct CanvasSyncResponse: Content, Sendable {
    let snapshotID: String
    let duplicate: Bool
    let capturedAt: Date
    let syncedAt: Date
    let counts: CanvasSyncCounts
}

struct CanvasIntegrationStatusResponse: Content {
    let connection: CanvasConnectionResponse
}
