import Foundation

/// A string an agent sends that we model as an enum but don't own.
///
/// Agents add event names and modes between releases. A closed enum turns
/// each addition into a decode failure that drops the whole event, so these
/// keep what they don't recognise and carry on.
public protocol OpenHookValue: Codable, Equatable, Sendable, RawRepresentable where RawValue == String {
    static var knownCases: [Self] { get }
    static func unknown(_ rawValue: String) -> Self
}

public extension OpenHookValue {
    static func resolved(_ rawValue: String) -> Self {
        knownCases.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    init?(rawValue: String) {
        self = Self.resolved(rawValue)
    }

    init(from decoder: any Decoder) throws {
        self = Self.resolved(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Field-level leniency for payload decoders: a field that changed type is
/// dropped, not fatal. Only the fields an event can't exist without
/// (`hook_event_name`, `session_id`) are still required.
extension KeyedDecodingContainer {
    func lenient<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Keeps the elements that decode, so one unfamiliar entry doesn't cost
    /// the rest of the list.
    func lenientList<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element]? {
        lenient([LossyElement<Element>].self, forKey: key)?.compactMap(\.value)
    }
}

/// One array element that may fail to decode, so a single bad entry doesn't
/// fail the array around it.
public struct LossyElement<Value: Decodable>: Decodable {
    public var value: Value?

    public init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
