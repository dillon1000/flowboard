import Fluent
import Vapor

enum BoardPermission {
    case view
    case comment
    case edit
    case admin
}

struct BoardAccess {
    let board: Board
    let role: BoardMemberRole
    let isOwner: Bool
}

enum BoardAccessService {
    /// Returns every owned or shared board ID for one user. The set removes a
    /// duplicate if legacy data also contains a membership for a board owner.
    static func boardIDs(for userID: UUID, on database: any Database) async throws -> [UUID] {
        let owned = try await Board.query(on: database)
            .filter(\.$owner.$id == userID)
            .all()
            .compactMap(\.id)
        let shared = try await BoardMember.query(on: database)
            .filter(\.$user.$id == userID)
            .all()
            .map(\.$board.id)
        return Array(Set(owned + shared))
    }

    /// Resolves a board and verifies the requested permission. Missing and denied
    /// boards both return 404 so the endpoint does not disclose private board IDs.
    static func require(
        boardID: UUID,
        userID: UUID,
        permission: BoardPermission,
        on database: any Database
    ) async throws -> BoardAccess {
        guard let board = try await Board.find(boardID, on: database) else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }

        if board.$owner.id == userID {
            return BoardAccess(board: board, role: .admin, isOwner: true)
        }

        guard let member = try await BoardMember.query(on: database)
            .filter(\.$board.$id == boardID)
            .filter(\.$user.$id == userID)
            .first(),
            allows(member.role, permission: permission)
        else {
            throw Abort(.notFound, reason: "The board does not exist.")
        }

        return BoardAccess(board: board, role: member.role, isOwner: false)
    }

    private static func allows(_ role: BoardMemberRole, permission: BoardPermission) -> Bool {
        switch permission {
        case .view:
            true
        case .comment:
            role.canComment
        case .edit:
            role.canEdit
        case .admin:
            role == .admin
        }
    }
}
