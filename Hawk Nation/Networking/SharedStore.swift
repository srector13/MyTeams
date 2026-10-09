//
//  SharedStore.swift
//  myTeams
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import OSLog
import Security
import Synchronization

private let logger = Logger(subsystem: "com.myTeams", category: "sharedStore")

// Compiled into both targets, like `LogoStore`: the app writes what the
// widget reads, and both must agree on where.

// MARK: - Signing entitlements

/// What this process was signed with, as far as sharing goes, read from the
/// entitlements in its own executable's code signature.
///
/// A re-signer (Feather's zsign) signs the app and the widget with one
/// provisioning profile and gives both that profile's entitlements: its App
/// Groups, whatever they are named, and its keychain access groups, not the
/// `group.PolarReailty.Hawk-Nation` the project asks for. The store the two
/// processes share is the one the install was actually signed with, so both
/// read it from here and pick it the same way (`SharedStoreIdentity`).
struct SigningEntitlements: Equatable, Sendable {
    /// `com.apple.security.application-groups`; empty when the signature
    /// carries none.
    var appGroups: [String]
    /// `keychain-access-groups`; empty when the signature carries none.
    var keychainAccessGroups: [String]
    /// `application-identifier`. zsign signs the widget with the app's, so
    /// under a re-signer it is a keychain group both processes hold even
    /// when the profile lists none.
    var applicationIdentifier: String?

    init(appGroups: [String] = [], keychainAccessGroups: [String] = [], applicationIdentifier: String? = nil) {
        self.appGroups = appGroups
        self.keychainAccessGroups = keychainAccessGroups
        self.applicationIdentifier = applicationIdentifier
    }

    /// A signature's entitlements plist; `nil` when it isn't one.
    init?(plist data: Data) {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let entitlements = object as? [String: Any]
        else { return nil }
        appGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        keychainAccessGroups = entitlements["keychain-access-groups"] as? [String] ?? []
        applicationIdentifier = entitlements["application-identifier"] as? String
    }

    /// This process's, read once. `nil` when its executable carries no
    /// entitlements, as an unsigned Simulator build's doesn't: then nothing
    /// can be said, and the project's own group is used, as ever.
    static let current: SigningEntitlements? = {
        guard let url = Bundle.main.executableURL,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        let plist = MachOSignature.entitlements { offset, count in
            do {
                try handle.seek(toOffset: offset)
                return try handle.read(upToCount: count)
            } catch {
                return nil
            }
        }
        return plist.flatMap(SigningEntitlements.init(plist:))
    }()
}

/// Finds the entitlements plist in a Mach-O executable's code signature.
///
/// Reads the headers and the signature only, through `read`, never the
/// whole binary: the widget's memory is tight.
enum MachOSignature {
    /// Reads `count` bytes at `offset`; `nil` or fewer bytes past the end.
    typealias Reader = (_ offset: UInt64, _ count: Int) -> Data?

    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let magic32: UInt32 = 0xFEED_FACE
    static let magic64: UInt32 = 0xFEED_FACF
    static let cpuTypeARM64: UInt32 = 0x0100_000C
    static let loadCodeSignature: UInt32 = 0x1D
    static let superBlobMagic: UInt32 = 0xFADE_0CC0
    static let entitlementsMagic: UInt32 = 0xFADE_7171
    static let entitlementsSlot: UInt32 = 5

    /// More than any real header or signature: a bound against a corrupt
    /// count asking for gigabytes.
    private static let sizeLimit = 16 * 1024 * 1024

    /// The entitlements plist, or `nil` when the executable has no signature
    /// or its signature none.
    static func entitlements(read: Reader) -> Data? {
        guard let head = read(0, 8), head.count == 8 else { return nil }
        let fat = head.uint32(at: 0, bigEndian: true)
        guard fat == fatMagic || fat == fatMagic64 else {
            return entitlements(sliceAt: 0, read: read)
        }
        // A universal binary: the arm64 slice, which is what iOS runs, else
        // the first.
        let wide = fat == fatMagic64
        let count = Int(head.uint32(at: 4, bigEndian: true))
        let entrySize = wide ? 32 : 20
        guard count > 0, count < 64,
              let entries = read(8, count * entrySize), entries.count == count * entrySize
        else { return nil }
        var chosen: UInt64?
        for index in 0..<count {
            let base = index * entrySize
            let offset = wide
                ? entries.uint64(at: base + 8, bigEndian: true)
                : UInt64(entries.uint32(at: base + 8, bigEndian: true))
            if entries.uint32(at: base, bigEndian: true) == cpuTypeARM64 {
                chosen = offset
                break
            }
            chosen = chosen ?? offset
        }
        return chosen.flatMap { entitlements(sliceAt: $0, read: read) }
    }

    /// The entitlements of the thin Mach-O at `slice`.
    private static func entitlements(sliceAt slice: UInt64, read: Reader) -> Data? {
        guard let header = read(slice, 32), header.count >= 28 else { return nil }
        let headerSize: Int
        switch header.uint32(at: 0, bigEndian: false) {
        case magic64: headerSize = 32
        case magic32: headerSize = 28
        default: return nil
        }
        let commandCount = Int(header.uint32(at: 16, bigEndian: false))
        let commandsSize = Int(header.uint32(at: 20, bigEndian: false))
        guard commandCount > 0, commandsSize > 0, commandsSize < sizeLimit,
              let commands = read(slice + UInt64(headerSize), commandsSize), commands.count == commandsSize
        else { return nil }

        var cursor = 0
        for _ in 0..<commandCount {
            guard cursor + 8 <= commands.count else { return nil }
            let command = commands.uint32(at: cursor, bigEndian: false)
            let size = Int(commands.uint32(at: cursor + 4, bigEndian: false))
            guard size >= 8 else { return nil }
            if command == loadCodeSignature {
                guard cursor + 16 <= commands.count else { return nil }
                let offset = UInt64(commands.uint32(at: cursor + 8, bigEndian: false))
                let length = Int(commands.uint32(at: cursor + 12, bigEndian: false))
                return entitlements(inSignature: slice + offset, length: length, read: read)
            }
            cursor += size
        }
        return nil
    }

    /// The entitlements blob's plist in the signature's super blob.
    private static func entitlements(inSignature offset: UInt64, length: Int, read: Reader) -> Data? {
        guard length >= 12, length < sizeLimit,
              let blob = read(offset, length), blob.count == length,
              blob.uint32(at: 0, bigEndian: true) == superBlobMagic
        else { return nil }
        let count = Int(blob.uint32(at: 8, bigEndian: true))
        for index in 0..<count {
            let entry = 12 + index * 8
            guard entry + 8 <= blob.count else { return nil }
            guard blob.uint32(at: entry, bigEndian: true) == entitlementsSlot else { continue }
            let start = Int(blob.uint32(at: entry + 4, bigEndian: true))
            guard start + 8 <= blob.count,
                  blob.uint32(at: start, bigEndian: true) == entitlementsMagic
            else { return nil }
            let size = Int(blob.uint32(at: start + 4, bigEndian: true))
            guard size >= 8, start + size <= blob.count else { return nil }
            return blob.subdata(in: (blob.startIndex + start + 8)..<(blob.startIndex + start + size))
        }
        return nil
    }
}

private extension Data {
    /// Four bytes at `offset`; 0 past the end.
    func uint32(at offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        for index in 0..<4 {
            let byte = self[startIndex + offset + (bigEndian ? index : 3 - index)]
            value = value << 8 | UInt32(byte)
        }
        return value
    }

    /// Eight bytes at `offset`; 0 past the end.
    func uint64(at offset: Int, bigEndian: Bool) -> UInt64 {
        let first = UInt64(uint32(at: offset, bigEndian: bigEndian))
        let second = UInt64(uint32(at: offset + 4, bigEndian: bigEndian))
        return bigEndian ? first << 32 | second : second << 32 | first
    }
}

// MARK: - Shared store identity

/// Where the app and the widget meet: an App Group, and a keychain access
/// group, both picked from the signature the same way in both processes.
///
/// The project's group when the signature carries it, as an Xcode-signed
/// build's does. A re-signed install's own group otherwise, since zsign
/// gives the app and the widget the same profile's groups. The keychain
/// group carries the favorites when no App Group does (a wildcard profile,
/// which has none).
///
/// The keychain group is the signature's own string, never one derived
/// from it: securityd matches an item's access group against the client's
/// entitlement exactly, with only a bare `"*"` as a wildcard
/// (`SecServerAccessGroupsAllows`), so a wildcard profile's `TEAMID.*`
/// grants the literal group `TEAMID.*` and nothing under it. Filling the
/// `*` in, as 1.0.16 did, asked for a group neither process holds, and every
/// read and write failed with `errSecMissingEntitlement` (t_684fd0fb).
struct SharedStoreIdentity: Equatable, Sendable {
    /// The App Group the project's entitlements name.
    static let canonicalGroup = "group.PolarReailty.Hawk-Nation"
    /// The App Group to share through; `nil` when the signature has none.
    var appGroup: String?
    /// The keychain access group both processes hold; `nil` when the
    /// signature names none.
    var keychainGroup: String?

    /// The identity a signature gives: with none readable, the project's
    /// group and no keychain group, as before re-signed installs were told
    /// apart.
    static func resolve(_ signed: SigningEntitlements?) -> SharedStoreIdentity {
        guard let signed else {
            return SharedStoreIdentity(appGroup: canonicalGroup, keychainGroup: nil)
        }
        return SharedStoreIdentity(
            appGroup: appGroup(in: signed.appGroups),
            keychainGroup: keychainGroup(in: signed.keychainAccessGroups, applicationIdentifier: signed.applicationIdentifier)
        )
    }

    /// The project's group, else one named for the app (AltStore appends a
    /// team id), else the profile's first: the same in both processes, as
    /// zsign signs both with the same list.
    static func appGroup(in groups: [String]) -> String? {
        if groups.contains(canonicalGroup) {
            return canonicalGroup
        }
        return groups.first { $0.localizedCaseInsensitiveContains("Hawk-Nation") } ?? groups.first
    }

    /// The first keychain group, as signed (a wildcard profile's `TEAMID.*`
    /// included), else the application identifier, which a re-signer gives
    /// the widget too. `nil` with neither.
    static func keychainGroup(in groups: [String], applicationIdentifier: String? = nil) -> String? {
        groups.first ?? applicationIdentifier.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// This process's.
    static let current = resolve(SigningEntitlements.current)

    /// What the signature offers, for a widget saying why it has no data:
    /// "App Group group.… · Keychain TEAMID.…".
    var summary: String {
        let group = appGroup.map { "App Group \($0)" } ?? "No App Group in signature"
        let keychain = keychainGroup.map { "Keychain \($0)" } ?? "no keychain group"
        return "\(group) · \(keychain)"
    }
}

// MARK: - Keychain

/// Where the app and the widget keep a shared item outside an App Group:
/// the keychain (`SharedKeychain`), or a test's stand-in.
protocol SharedSecretStore: Sendable {
    /// The access group the item lives in.
    var accessGroup: String { get }
    /// The item's data and the read's status.
    func read(_ account: String) -> (data: Data?, status: OSStatus)
    /// Writes the item; returns the status.
    @discardableResult
    func write(_ data: Data, for account: String) -> OSStatus
}

extension SharedSecretStore {
    /// The item's data; `nil` when there is none or the group can't be read.
    func data(for account: String) -> Data? {
        read(account).data
    }

    /// Writes the item; returns whether it was written.
    @discardableResult
    func set(_ data: Data, for account: String) -> Bool {
        write(data, for: account) == errSecSuccess
    }
}

/// A keychain item the app writes and the widget reads, in an access group
/// both are signed with: the favorites' path when no App Group carries them.
struct SharedKeychain: SharedSecretStore, Equatable {
    static let service = "PolarReailty.Hawk-Nation.shared"

    let accessGroup: String

    /// The item's data and the read's status, for the diagnostics:
    /// `errSecItemNotFound` (-25300) before the app has written it,
    /// `errSecMissingEntitlement` (-34018) for a group the signature lacks.
    func read(_ account: String) -> (data: Data?, status: OSStatus) {
        var query = item(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.error("Keychain read from \(self.accessGroup) failed: \(status)")
            }
            return (nil, status)
        }
        return (result as? Data, status)
    }

    /// Writes the item, readable after the first unlock so the Lock Screen
    /// widgets can read it. The status is kept for the app's diagnostics.
    @discardableResult
    func write(_ data: Data, for account: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(item(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = item(account).merging(attributes) { $1 }
            status = SecItemAdd(added as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain write to \(self.accessGroup) failed: \(status)")
        }
        SharedKeychain.lastWriteStatus.withLock { $0 = status }
        return status
    }

    /// The status of this process's last write, `nil` before any: the app's
    /// diagnostics show it beside the widget's read.
    static let lastWriteStatus = Mutex<OSStatus?>(nil)

    private func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }
}

// MARK: - Favorites mirror

/// The favorites as teams, written by the app where the widget reads them:
/// the shared group's defaults, and the shared keychain item.
///
/// Teams, not only ids: the widget draws a favorite and offers it in its
/// configuration without loading the favorite's league catalog, which,
/// without a cache shared with the app, it would fetch and parse whole,
/// slowly and at a cost the extension's memory can't afford. Its
/// `writtenAt` is also the proof that the store the widget reads is the one
/// the app writes (`SharedContainer.status`).
struct SharedFavoritesMirror: Codable, Equatable, Sendable {
    static let defaultsKey = "sharedStore.favorites.v1"
    static let keychainAccount = "favorites.v1"

    /// The favorites' `TeamRef.id`s, in order.
    var ids: [TeamRef.ID]
    /// The favorites the app had resolved, in order; one still resolving
    /// is left out, and the widget looks it up itself.
    var teams: [TeamRef]
    /// When the app wrote it.
    var writtenAt: Date

    func encoded() -> Data? {
        try? Self.encoder.encode(self)
    }

    /// `nil` for missing or unreadable data.
    static func decode(_ data: Data?) -> SharedFavoritesMirror? {
        guard let data else { return nil }
        return try? decoder.decode(SharedFavoritesMirror.self, from: data)
    }

    /// Writes the favorites to `defaults` (the store the app shares
    /// through, `SharedPaths.defaults`) and to the shared keychain item,
    /// where either differs; returns whether anything was written, so the
    /// caller reloads the widgets then. A placeholder team
    /// (`TeamRef.placeholder(id:)`) is left out of `teams`.
    @discardableResult
    static func publish(
        ids: [TeamRef.ID],
        teams: [TeamRef],
        at now: Date = Date(),
        defaults: UserDefaults = SharedPaths.defaults,
        keychain: (any SharedSecretStore)? = SharedContainer.live.keychain
    ) -> Bool {
        let resolved = teams.filter { $0 != TeamRef.placeholder(id: $0.id) }
        func current(_ mirror: SharedFavoritesMirror?) -> Bool {
            mirror?.ids == ids && mirror?.teams == resolved
        }
        let inDefaults = current(decode(defaults.data(forKey: defaultsKey)))
        let inKeychain = keychain.map { current(decode($0.data(for: keychainAccount))) } ?? true
        guard !inDefaults || !inKeychain,
              let data = SharedFavoritesMirror(ids: ids, teams: resolved, writtenAt: now).encoded()
        else { return false }
        if !inDefaults {
            defaults.set(data, forKey: defaultsKey)
        }
        if !inKeychain {
            keychain?.set(data, for: keychainAccount)
        }
        return true
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Diagnostics

/// What one process knows about the store it shares through, drawn on the
/// widget's face and in the app's Settings so the two can be compared side
/// by side on a re-signed device: its bundle id, the groups its own
/// signature carries, the store it chose, and how many favorites it read.
struct SharedStoreDiagnostics: Equatable, Sendable {
    /// "app" or "widget".
    var process: String
    var bundleID: String
    /// The process's signature; `nil` when it carries no entitlements.
    var signed: SigningEntitlements?
    var identity: SharedStoreIdentity
    var status: SharedDataStatus
    /// The favorites read through the chosen store.
    var favoritesCount: Int
    /// The keychain item's read; `nil` without a keychain group.
    var keychainRead: OSStatus?
    /// The app's last keychain write; `nil` before any, and in the widget.
    var keychainWrite: OSStatus? = nil

    /// One line each, for the widget's no-team face and the app's
    /// Settings.
    var lines: [String] {
        var lines = [
            "\(process) \(bundleID)",
            "groups: \(Self.list(signed?.appGroups))",
            "keychain: \(Self.list(signed?.keychainAccessGroups))",
            "store: \(store)",
            "favorites: \(favoritesCount)",
        ]
        if let keychainRead, let group = identity.keychainGroup {
            var line = "keychain \(group) read \(keychainRead)"
            if let keychainWrite { line += " · write \(keychainWrite)" }
            lines.append(line)
        }
        return lines
    }

    /// One line for a tile: "widget · Keychain ABCDE12345.* · fav 3".
    var compact: String {
        "\(process) · \(store) · fav \(favoritesCount)"
    }

    /// The store chosen and whether the app's data is in it.
    var store: String {
        switch status {
        case .available: return SharedStore.appGroup(SharedStoreIdentity.canonicalGroup).detail
        case .fallback(let store, _): return store.detail
        case .unshared(let store): return "\(store.detail) (empty)"
        case .unavailable: return "none"
        }
    }

    private static func list(_ values: [String]?) -> String {
        guard let values else { return "unsigned" }
        return values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    /// `diagnostics`, unless the project's App Group carries the app's
    /// data: an Xcode-signed install's widgets keep their faces clean.
    static func shown(_ diagnostics: SharedStoreDiagnostics) -> SharedStoreDiagnostics? {
        if case .available = diagnostics.status { return nil }
        return diagnostics
    }

    /// This process's, read now.
    static func current(in container: SharedContainer = .live) -> SharedStoreDiagnostics {
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        return SharedStoreDiagnostics(
            process: isExtension ? "widget" : "app",
            bundleID: Bundle.main.bundleIdentifier ?? "?",
            signed: SigningEntitlements.current,
            identity: SharedStoreIdentity.current,
            status: container.status,
            favoritesCount: container.favoriteTeamIDs().count,
            keychainRead: container.keychain?.read(SharedFavoritesMirror.keychainAccount).status,
            keychainWrite: isExtension ? nil : SharedKeychain.lastWriteStatus.withLock { $0 }
        )
    }
}

// MARK: - Moving the favorites

/// Carries the favorites into the store the signature picks, the first time
/// the app runs with it.
///
/// Builds before this one kept them in the project's group's defaults, or,
/// without it, in the app's own; a re-signed install now shares through its
/// own group or none, and must not open on "Add Teams".
enum SharedStoreMigration {
    /// Copies the favorites, and the seed flag, from the first of `sources`
    /// holding a list, unless `target` has one already. Returns whether it
    /// copied.
    @discardableResult
    static func moveFavorites(into target: UserDefaults, from sources: [UserDefaults]) -> Bool {
        guard target.data(forKey: FavoritesCodec.key) == nil else { return false }
        for source in sources where source !== target {
            guard let data = source.data(forKey: FavoritesCodec.key), FavoritesCodec.decodeEntries(data) != nil else {
                continue
            }
            target.set(data, forKey: FavoritesCodec.key)
            target.set(true, forKey: FavoritesCodec.seededKey)
            logger.notice("Moved the favorites into the shared store")
            return true
        }
        return false
    }

    /// The app's launch: from its own defaults, and the project's group's,
    /// into `SharedPaths.defaults`.
    static func moveFavoritesIfNeeded() {
        var sources: [UserDefaults] = [.standard]
        if SharedContainer.live.groupID != SharedStoreIdentity.canonicalGroup,
           let canonical = UserDefaults(suiteName: SharedStoreIdentity.canonicalGroup) {
            sources.append(canonical)
        }
        moveFavorites(into: SharedPaths.defaults, from: sources)
    }
}

// MARK: - Deadlines

/// Resumes a continuation once, from whichever of a race finishes first.
private final class RaceGate<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Never>?>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: Value) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }
}

enum Deadline {
    /// `operation`'s value, or `nil` once `deadline` passes, without waiting
    /// for an operation that ignores cancellation (`RemoteTeamCatalog`'s
    /// shared loads do). A task group would wait for it.
    static func value<Value: Sendable>(
        within deadline: Duration,
        of operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let gate = RaceGate(continuation)
            let work = Task {
                gate.resume(await operation())
            }
            Task {
                try? await Task.sleep(for: deadline)
                work.cancel()
                gate.resume(nil)
            }
        }
    }
}
