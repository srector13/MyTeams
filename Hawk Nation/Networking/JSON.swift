//
//  JSON.swift
//  myTeams
//
//  A dependency-free replacement for the SwiftyJSON package.
//
//  The ESPN endpoints this app talks to return large, loosely-specified
//  documents whose shape varies by sport, by season, and by whether a game has
//  been played yet. Rather than model every one of them with Codable types,
//  the parsing code walks the raw document by key path and falls back to a zero
//  value whenever something is missing. This type provides that traversal on
//  top of JSONSerialization, matching the lenient coercion rules the parsing
//  code was written against.
//

import Foundation

/// A single node in a parsed JSON document.
///
/// Subscripting never fails: addressing a key that does not exist, or indexing
/// into something that is not an array, yields a `null` node whose typed
/// accessors return zero values. This lets a key path be read in one
/// expression without unwrapping each step.
public enum JSON: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSON])
    case object([String: JSON])
    case null

    // MARK: - Creating

    /// Wraps the output of `JSONSerialization.jsonObject(with:)`.
    public init(_ raw: Any?) {
        switch raw {
        case let json as JSON:
            self = json
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            // JSONSerialization boxes booleans and numbers alike in NSNumber,
            // and bridging `1` to Bool succeeds just as readily as `true`
            // does. The encoded Objective-C type is what actually separates
            // them: booleans report "c", numbers report "q" or "d".
            self = number.objCType.pointee == UInt8(ascii: "c").asCChar
                ? .bool(number.boolValue)
                : .number(number.doubleValue)
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .number(Double(int))
        case let double as Double:
            self = .number(double)
        case let array as [Any]:
            self = .array(array.map(JSON.init))
        case let object as [String: Any]:
            self = .object(object.mapValues(JSON.init))
        default:
            self = .null
        }
    }

    /// Parses raw response bytes. Returns `.null` if the data is not JSON.
    public init(data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) else {
            self = .null
            return
        }
        self.init(raw)
    }

    // MARK: - Traversing

    /// One step in a key path: either a dictionary key or an array index.
    public enum Index: Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
        case key(String)
        case index(Int)

        public init(stringLiteral value: String) { self = .key(value) }
        public init(integerLiteral value: Int) { self = .index(value) }
    }

    public subscript(key: String) -> JSON {
        guard case .object(let object) = self else { return .null }
        return object[key] ?? .null
    }

    public subscript(index: Int) -> JSON {
        guard case .array(let array) = self, array.indices.contains(index) else { return .null }
        return array[index]
    }

    /// Walks a multi-step key path, e.g. `json["boxscore", "teams", 0, "team", "name"]`.
    ///
    /// The first two steps are separate parameters rather than a single
    /// variadic so that a one-step subscript is never ambiguous with the
    /// `String` and `Int` overloads above.
    public subscript(first: Index, second: Index, rest: Index...) -> JSON {
        self[[first, second] + rest]
    }

    public subscript(path: [Index]) -> JSON {
        path.reduce(self) { node, step in
            switch step {
            case .key(let key): node[key]
            case .index(let index): node[index]
            }
        }
    }

    // MARK: - Typed access

    /// The node as a string, or `nil` if it holds something else.
    public var string: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    /// The node as a string, coercing numbers and booleans and defaulting to `""`.
    public var stringValue: String {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            // Render whole numbers without a trailing ".0", matching how the
            // values appear in the source document.
            return number == number.rounded() && abs(number) < 1e15
                ? String(Int64(number))
                : String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array, .object, .null:
            return ""
        }
    }

    /// The node as a number. Strings are parsed leniently: a leading numeric
    /// run is accepted, so display values such as `"45.5"` or `"312 yds"` read
    /// as numbers, and anything unparseable is `nil`.
    public var number: Double? {
        switch self {
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? 1 : 0
        case .string(let string):
            let decimal = NSDecimalNumber(string: string)
            return decimal == .notANumber ? nil : decimal.doubleValue
        case .array, .object, .null:
            return nil
        }
    }

    public var double: Double? { number }
    public var doubleValue: Double { number ?? 0 }

    public var float: Float? { number.map(Float.init) }
    public var floatValue: Float { Float(number ?? 0) }

    public var int: Int? {
        guard let number, number.isFinite else { return nil }
        return Int(number)
    }
    public var intValue: Int { int ?? 0 }

    /// The node as a boolean. Numbers are true when non-zero, and the strings
    /// `"true"`, `"yes"`, `"y"`, `"t"` and `"1"` are true.
    public var bool: Bool? {
        switch self {
        case .bool(let bool):
            return bool
        case .number(let number):
            return number != 0
        case .string(let string):
            switch string.lowercased() {
            case "true", "yes", "y", "t", "1": return true
            case "false", "no", "n", "f", "0": return false
            default: return nil
            }
        case .array, .object, .null:
            return nil
        }
    }
    public var boolValue: Bool { bool ?? false }

    public var array: [JSON]? {
        guard case .array(let array) = self else { return nil }
        return array
    }
    public var arrayValue: [JSON] { array ?? [] }

    public var dictionary: [String: JSON]? {
        guard case .object(let object) = self else { return nil }
        return object
    }
    public var dictionaryValue: [String: JSON] { dictionary ?? [:] }

    /// Whether the node is missing or explicitly null.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Whether the node holds a value that is neither missing nor empty.
    public var exists: Bool { !isNull }
}

// MARK: - Iteration

/// Iterating a node visits its children as `(key, value)` pairs: dictionary
/// keys for an object, stringified positions for an array, and nothing at all
/// for a leaf. Parsing code relies on the leaf case to skip absent collections
/// without a prior existence check.
extension JSON: Sequence {
    public func makeIterator() -> AnyIterator<(String, JSON)> {
        switch self {
        case .object(let object):
            var iterator = object.makeIterator()
            return AnyIterator { iterator.next() }
        case .array(let array):
            var index = array.startIndex
            return AnyIterator {
                guard index < array.endIndex else { return nil }
                defer { index += 1 }
                return (String(index), array[index])
            }
        case .string, .number, .bool, .null:
            return AnyIterator { nil }
        }
    }
}

private extension UInt8 {
    /// `CChar` is signed on Apple platforms and unsigned on some others, so
    /// comparing against `objCType` needs the platform's own character type.
    var asCChar: CChar { CChar(bitPattern: self) }
}

extension JSON: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let string): "\"\(string)\""
        case .number, .bool: stringValue
        case .array(let array): "[\(array.map(\.description).joined(separator: ","))]"
        case .object(let object):
            "{\(object.map { "\"\($0.key)\":\($0.value.description)" }.joined(separator: ","))}"
        case .null: "null"
        }
    }
}
