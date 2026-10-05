//
//  FixtureLoader.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

@testable import myTeams

/// Loads the captured ESPN documents in `myTeamsTests/Fixtures`.
///
/// The folder is a folder reference in the `myTeamsTests` Resources phase, so
/// the bundle carries it as `Fixtures/<name>.json`. If the bundle copy is
/// missing — a target edited by hand, or a test run from a tool that skips
/// the Resources phase — the loader falls back to the source tree beside this
/// file, which is where the fixtures live in the repository. See FIXTURES.md.
enum Fixture {
    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case notJSON(String)

        var description: String {
            switch self {
            case .missing(let name): "Fixture \(name).json is in neither the test bundle nor the source tree"
            case .notJSON(let name): "Fixture \(name).json did not parse as JSON"
            }
        }
    }

    /// Anchors `Bundle(for:)` to the test bundle; Swift Testing suites are
    /// structs, which that initialiser cannot take.
    private final class BundleToken {}

    /// The fixture's URL, preferring the copy bundled with the tests.
    static func url(_ name: String) throws -> URL {
        if let bundled = Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return bundled
        }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw LoadError.missing(name)
        }
        return source
    }

    /// The folder the fixtures are read from, bundled or in the source tree,
    /// for a `FixtureTransport` to serve.
    static func directory() throws -> URL {
        try url("chiefs_schedule").deletingLastPathComponent()
    }

    /// The fixture parsed as a `JSON` document, e.g. `Fixture.json("chiefs_schedule")`.
    static func json(_ name: String) throws -> JSON {
        let json = JSON(data: try Data(contentsOf: url(name)))
        guard !json.isNull else { throw LoadError.notJSON(name) }
        return json
    }

    /// The event with ESPN id `id` in a schedule fixture, and its position in
    /// the feed (which `parseGame` records as `pointer`).
    static func event(_ id: String, in schedule: JSON) throws -> (event: JSON, pointer: Int) {
        for (offset, element) in schedule["events"].enumerated()
        where element.1["id"].stringValue == id {
            return (element.1, offset)
        }
        throw LoadError.missing("event \(id)")
    }
}

extension JSON {
    /// A copy of this document with the node at `path` replaced by `value`.
    ///
    /// Lets a test derive a variant from a real fixture — one status string
    /// or one date swapped — instead of hand-writing a synthetic document. A
    /// path that runs through a missing key or out of an array's bounds
    /// leaves the document unchanged.
    func setting(_ path: [JSON.Index], to value: JSON) -> JSON {
        guard let step = path.first else { return value }
        let rest = Array(path.dropFirst())

        switch (self, step) {
        case (.object(var object), .key(let key)):
            guard let child = object[key] else {
                // Only a final step may add a key.
                guard rest.isEmpty else { return self }
                object[key] = value
                return .object(object)
            }
            object[key] = child.setting(rest, to: value)
            return .object(object)
        case (.array(var array), .index(let index)) where array.indices.contains(index):
            array[index] = array[index].setting(rest, to: value)
            return .array(array)
        default:
            return self
        }
    }
}

extension JSON {
    /// The document as bytes again, so a `RecordingTransport` can serve a
    /// variant built with `setting(_:to:)`.
    func serialized() throws -> Data {
        try JSONSerialization.data(withJSONObject: foundationValue)
    }

    private var foundationValue: Any {
        switch self {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .array(let array): return array.map(\.foundationValue)
        case .object(let object): return object.mapValues(\.foundationValue)
        case .null: return NSNull()
        }
    }
}
