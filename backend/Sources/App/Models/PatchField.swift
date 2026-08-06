import Vapor

/// Distinguishes a missing JSON property from an explicit `null` in PATCH requests.
/// Missing fields stay unchanged, `null` clears nullable values, and a value replaces
/// the current value. Invalid JSON fails during normal Content decoding.
@propertyWrapper
struct PatchField<Value: Codable & Sendable>: Codable, Sendable {
    enum State: Sendable {
        case omitted
        case null
        case value(Value)
    }

    var wrappedValue: State

    init() {
        self.wrappedValue = .omitted
    }

    init(_ state: State) {
        self.wrappedValue = state
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = if container.decodeNil() {
            .null
        } else {
            .value(try container.decode(Value.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch wrappedValue {
        case .omitted, .null:
            try container.encodeNil()
        case let .value(value):
            try container.encode(value)
        }
    }
}

extension PatchField.State {
    /// A supplied null still counts as a requested change for managed-field checks.
    var isSupplied: Bool {
        if case .omitted = self { return false }
        return true
    }
}

extension KeyedDecodingContainer {
    /// Swift's synthesized decoder normally treats a missing property wrapper as
    /// an error. This overload supplies the wrapper's omitted state instead.
    func decode<Value>(
        _ type: PatchField<Value>.Type,
        forKey key: Key
    ) throws -> PatchField<Value> where Value: Codable & Sendable {
        guard contains(key) else { return PatchField() }
        guard try !decodeNil(forKey: key) else { return PatchField(.null) }
        return try decodeIfPresent(type, forKey: key) ?? PatchField()
    }
}
