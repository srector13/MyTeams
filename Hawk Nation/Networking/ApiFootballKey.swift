//
//  ApiFootballKey.swift
//  myTeams
//
//  Created by Stephen Rector on 10/7/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import Security

// MARK: - Secret storage

/// Where one secret is kept: the Keychain in the app, memory in tests (the
/// unsigned simulator test host has no Keychain entitlement).
protocol SecretStorage: Sendable {
    /// The stored secret, or `nil` when there is none or it cannot be read.
    func read() -> String?
    /// Stores `secret` in place of any before it. `false` when it could not.
    @discardableResult func write(_ secret: String) -> Bool
    /// Removes the secret, if any.
    func delete()
}

/// A generic-password Keychain item, readable after the device's first
/// unlock so a launch in the background still finds it. Never mirrored to
/// `UserDefaults`, never logged.
struct KeychainSecretStorage: SecretStorage {
    /// The account the API-Football key is stored under.
    static let apiFootballAccount = "apifootball.key"

    let service: String
    let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.myTeams",
        account: String = KeychainSecretStorage.apiFootballAccount
    ) {
        self.service = service
        self.account = account
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ secret: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        let item = itemQuery.merging(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        _ = SecItemDelete(itemQuery as CFDictionary)
    }
}

// MARK: - Key

/// The reader's own API-Football key: its clean-up and how it is shown.
enum ApiFootballKey {
    /// `draft` without surrounding whitespace, or `nil` when nothing is left.
    static func normalized(_ draft: String) -> String? {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// The key's last four characters: all Settings ever shows of it.
    static func suffix(_ key: String) -> String {
        String(key.suffix(4))
    }
}

/// What the `/status` probe made of a key.
enum ApiFootballProbe: Equatable, Sendable {
    case idle
    case checking
    /// The key works. `summary` is e.g. "Free plan, 3 of 100 requests used today".
    case accepted(summary: String)
    /// The key was refused, or could not be checked; nothing was saved.
    case failed(message: String)
}

// MARK: - Settings

/// Settings → API-Football: the reader's key (Keychain only) and whether
/// it is used for photos ESPN and Wikidata lack.
///
/// No request reaches API-Football or its CDN unless `activeKey()` gives a
/// key: the toggle on and a key saved.
@MainActor
@Observable
final class ApiFootballSettings {
    static let shared = ApiFootballSettings()

    /// The `UserDefaults` key for the toggle. The key itself is never there.
    static let enabledKey = "settings.apiFootball.enabled"

    /// Whether the toggle is on, as stored under `enabledKey`.
    var isEnabled: Bool {
        get { enabled }
        set {
            enabled = newValue
            defaults.set(newValue, forKey: Self.enabledKey)
        }
    }

    private var enabled: Bool

    /// The saved key's last four characters, or `nil` with none saved.
    private(set) var keySuffix: String?

    /// The last save's check, shown under the field.
    private(set) var probe: ApiFootballProbe = .idle

    @ObservationIgnored private let storage: any SecretStorage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: any KeyedHTTPTransport
    /// The key read once from storage, so drawing never touches the Keychain.
    @ObservationIgnored private var key: String?

    init(
        storage: any SecretStorage = KeychainSecretStorage(),
        defaults: UserDefaults = .standard,
        transport: any KeyedHTTPTransport = ApiFootball.session
    ) {
        self.storage = storage
        self.defaults = defaults
        self.transport = transport
        let key = storage.read()
        self.key = key
        keySuffix = key.map(ApiFootballKey.suffix)
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    var hasKey: Bool { keySuffix != nil }

    /// Whether API-Football may be asked anything.
    var isActive: Bool { isEnabled && hasKey }

    /// The key for a request: only while the toggle is on and a key is saved.
    func activeKey() -> String? {
        isActive ? key : nil
    }

    /// Checks `draft` with one `/status` request and saves it to the
    /// Keychain only if API-Football accepts it. The first key saved turns
    /// the toggle on.
    func save(_ draft: String) async {
        guard let candidate = ApiFootballKey.normalized(draft) else {
            probe = .failed(message: "Paste your API key first.")
            return
        }
        probe = .checking
        let outcome = await ApiFootball.probe(key: candidate, transport: transport)
        guard case .accepted = outcome else {
            probe = outcome
            return
        }
        guard storage.write(candidate) else {
            probe = .failed(message: "The key could not be saved to the Keychain.")
            return
        }
        let hadKey = hasKey
        key = candidate
        keySuffix = ApiFootballKey.suffix(candidate)
        if !hadKey { isEnabled = true }
        probe = outcome
    }

    /// Removes the key and turns the toggle off.
    func clear() {
        storage.delete()
        key = nil
        keySuffix = nil
        isEnabled = false
        probe = .idle
    }
}
