import Fluent
import Foundation
import Vapor

final class Board: Model, @unchecked Sendable {
    static let schema = "boards"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "slug")
    var slug: String

    @OptionalField(key: "description")
    var description: String?

    @Field(key: "is_archived")
    var isArchived: Bool

    /// Board-level definitions let each board add typed fields without changing
    /// the SQL schema for every new property that a user creates.
    @OptionalField(key: "property_definitions")
    var propertyDefinitions: [BoardPropertyDefinition]?

    /// These ordered JSON arrays define the choices shown for every task on this
    /// board. A nil value means that the board uses the standard choices.
    @OptionalField(key: "status_definitions")
    var statusDefinitions: [BoardTaskOption]?

    @OptionalField(key: "severity_definitions")
    var severityDefinitions: [BoardTaskOption]?

    @OptionalParent(key: "owner_id")
    var owner: User?

    @Children(for: \.$board)
    var tasks: [Task]

    @Children(for: \.$board)
    var views: [BoardView]

    @Children(for: \.$board)
    var members: [BoardMember]

    @Children(for: \.$board)
    var templates: [TaskTemplate]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        slug: String,
        description: String? = nil,
        ownerID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.isArchived = false
        self.propertyDefinitions = []
        self.statusDefinitions = BoardTaskOption.defaultStatuses
        self.severityDefinitions = BoardTaskOption.defaultSeverities
        self.$owner.id = ownerID
    }

    var taskStatuses: [BoardTaskOption] {
        statusDefinitions ?? BoardTaskOption.defaultStatuses
    }

    var taskSeverities: [BoardTaskOption] {
        severityDefinitions ?? BoardTaskOption.defaultSeverities
    }

    func statusOption(for status: TaskStatus) -> BoardTaskOption {
        taskStatuses.first { $0.id == status.rawValue }
            ?? BoardTaskOption.fallback(id: status.rawValue)
    }

    func severityOption(for priority: TaskPriority) -> BoardTaskOption {
        taskSeverities.first { $0.id == priority.rawValue }
            ?? BoardTaskOption.fallback(id: priority.rawValue)
    }

    func accepts(status: TaskStatus) -> Bool {
        taskStatuses.contains { $0.id == status.rawValue }
    }

    func accepts(priority: TaskPriority) -> Bool {
        taskSeverities.contains { $0.id == priority.rawValue }
    }

    func isCompleted(_ status: TaskStatus) -> Bool {
        statusOption(for: status).isCompleted
    }
}

/// A workflow color is either a theme-aware preset or a six-digit hex value.
/// The single-string encoding keeps existing board JSON and exports compatible.
struct BoardTaskOptionColor: RawRepresentable, Codable, Equatable, Sendable {
    let rawValue: String

    static let gray = Self("gray")
    static let blue = Self("blue")
    static let purple = Self("purple")
    static let green = Self("green")
    static let amber = Self("amber")
    static let orange = Self("orange")
    static let red = Self("red")
    static let presetPalette = [gray, blue, purple, green, amber, orange, red]

    private static let presetValues = Set(presetPalette.map(\.rawValue))
    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")

    init?(rawValue: String) {
        let normalized = rawValue.lowercased()
        let hexValue = normalized.dropFirst()
        let isHex = normalized.count == 7
            && normalized.first == "#"
            && hexValue.unicodeScalars.allSatisfy(Self.hexDigits.contains)
        guard Self.presetValues.contains(normalized) || isHex else { return nil }
        self.rawValue = normalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let color = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Workflow colors must be a preset or a six-digit hex value."
            )
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One board-owned status or severity choice. IDs are immutable task values,
/// while names and colors control how those values appear in the interface.
struct BoardTaskOption: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let color: BoardTaskOptionColor
    let isCompleted: Bool

    static let defaultStatuses = [
        Self(id: "backlog", name: "Backlog", color: .gray, isCompleted: false),
        Self(id: "in_progress", name: "In progress", color: .blue, isCompleted: false),
        Self(id: "review", name: "Review", color: .purple, isCompleted: false),
        Self(id: "done", name: "Done", color: .green, isCompleted: true),
    ]

    static let defaultSeverities = [
        Self(id: "low", name: "Low", color: .gray, isCompleted: false),
        Self(id: "medium", name: "Medium", color: .amber, isCompleted: false),
        Self(id: "high", name: "High", color: .orange, isCompleted: false),
        Self(id: "urgent", name: "Urgent", color: .red, isCompleted: false),
    ]

    static func fallback(id: String) -> Self {
        Self(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            color: .gray,
            isCompleted: id == TaskStatus.done.rawValue
        )
    }
}

enum BoardPropertyType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case select
    case multiSelect = "multi_select"
    case date
    case checkbox
    case url
    case email
    case person

    var usesOptions: Bool {
        self == .select || self == .multiSelect
    }
}

struct BoardPropertyOption: Codable, Sendable {
    let id: String
    let name: String
    let color: String
}

struct BoardPropertyDefinition: Codable, Sendable {
    let id: String
    let name: String
    let type: BoardPropertyType
    let options: [BoardPropertyOption]

    /// Converts the public string representation into the canonical value for
    /// this field type. Invalid values return nil and do not enter task data.
    func normalizedValue(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        switch type {
        case .text:
            return String(value.prefix(2_000))
        case .number:
            return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) == nil
                ? nil
                : value
        case .select:
            return options.contains { $0.id == value } ? value : nil
        case .multiSelect:
            let selected = Set(selectedOptionIDs(from: value))
            let normalized = options.map(\.id).filter(selected.contains)
            guard !normalized.isEmpty, let data = try? JSONEncoder().encode(normalized) else {
                return nil
            }
            return String(decoding: data, as: UTF8.self)
        case .date:
            return isValidDate(value) ? value : nil
        case .checkbox:
            return value == "true" ? value : nil
        case .url:
            guard
                let components = URLComponents(string: value),
                ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                components.host?.isEmpty == false
            else {
                return nil
            }
            return String(value.prefix(2_000))
        case .email:
            guard value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
                return nil
            }
            return String(value.prefix(320))
        case .person:
            return UUID(uuidString: value)?.uuidString.lowercased()
        }
    }

    /// Multi-select values remain strings in the task API. The string contains
    /// a JSON array of option IDs so option names can contain commas safely.
    func selectedOptionIDs(from value: String) -> [String] {
        guard
            let data = value.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        let allowed = Set(options.map(\.id))
        return decoded.filter(allowed.contains)
    }

    private func isValidDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let requested = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: requested) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == requested.year
            && actual.month == requested.month
            && actual.day == requested.day
    }
}

struct BoardResponse: Content {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let isArchived: Bool
    let propertyDefinitions: [BoardPropertyDefinition]
    let statusDefinitions: [BoardTaskOption]
    let severityDefinitions: [BoardTaskOption]
    let tasks: [TaskResponse]
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task] = []) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.description = board.description
        self.isArchived = board.isArchived
        self.propertyDefinitions = board.propertyDefinitions ?? []
        self.statusDefinitions = board.taskStatuses
        self.severityDefinitions = board.taskSeverities
        self.tasks = try tasks
            .sorted { left, right in
                let leftIndex = board.taskStatuses.firstIndex { option in
                    option.id == left.statusValue
                }
                    ?? board.taskStatuses.count
                let rightIndex = board.taskStatuses.firstIndex { option in
                    option.id == right.statusValue
                }
                    ?? board.taskStatuses.count
                return (leftIndex, left.position) < (rightIndex, right.position)
            }
            .map { try TaskResponse(task: $0) }
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}

struct CreateBoardRequest: Content, Validatable {
    let name: String
    let slug: String?
    let description: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add(
            "slug",
            as: String.self,
            is: .count(2...48) && .characterSet(.alphanumerics + CharacterSet(charactersIn: "-")),
            required: false
        )
        validations.add("description", as: String.self, is: .count(...500), required: false)
    }
}

struct UpdateBoardRequest: Content, Validatable {
    let name: String
    let description: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(2...80))
        validations.add("description", as: String.self, is: .count(...500), required: false)
    }
}

struct BoardSummaryResponse: Content {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let isArchived: Bool
    let taskCount: Int
    let completedCount: Int
    let createdAt: Date?
    let updatedAt: Date?

    init(board: Board, tasks: [Task]) throws {
        self.id = try board.requireID()
        self.name = board.name
        self.slug = board.slug
        self.description = board.description
        self.isArchived = board.isArchived
        self.taskCount = tasks.count
        self.completedCount = tasks.filter { board.isCompleted($0.status) }.count
        self.createdAt = board.createdAt
        self.updatedAt = board.updatedAt
    }
}
