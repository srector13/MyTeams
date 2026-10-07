//
//  ApiFootballKeyTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/7/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Stands in for the Keychain: the unsigned simulator test host has no
/// Keychain entitlement.
final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: String?

    init(_ secret: String? = nil) {
        self.secret = secret
    }

    func read() -> String? {
        lock.withLock { secret }
    }

    func write(_ secret: String) -> Bool {
        lock.withLock { self.secret = secret }
        return true
    }

    func delete() {
        lock.withLock { secret = nil }
    }
}

/// The reader's API-Football key: saved only after the `/status` probe
/// accepts it, kept only in `SecretStorage` (the Keychain in the app), never
/// in `UserDefaults`, and shown only by its last four characters. Uses a
/// made-up key; no test reaches the network.
@Suite("API-Football key")
@MainActor
struct ApiFootballKeyTests {
    /// Not a real key: the fixture probe accepts any.
    private static let key = "0123456789abcdef0123456789abWXYZ"

    private func scratchDefaults() throws -> (UserDefaults, String) {
        let suite = "ApiFootballKeyTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func probeTransport(_ fixture: String) -> RecordingTransport {
        RecordingTransport { _, _ in
            (try? RecordingTransport.Reply.fixture(fixture)) ?? .status(500)
        }
    }

    @Test("The Keychain item's account and the toggle's defaults key are fixed")
    func storageNamesAreStable() {
        // Changing either would lose every reader's saved key or choice.
        #expect(KeychainSecretStorage.apiFootballAccount == "apifootball.key")
        #expect(KeychainSecretStorage().account == "apifootball.key")
        #expect(ApiFootballSettings.enabledKey == "settings.apiFootball.enabled")
    }

    @Test("A key is trimmed, and blank is no key")
    func normalizing() {
        #expect(ApiFootballKey.normalized("  abc123 \n") == "abc123")
        #expect(ApiFootballKey.normalized(" \t\n") == nil)
        #expect(ApiFootballKey.suffix(Self.key) == "WXYZ")
    }

    @Test("Save, load and clear round-trip through the secret storage")
    func roundTrip() async throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = InMemorySecretStorage()
        let transport = probeTransport("apifootball_status_ok")
        let settings = ApiFootballSettings(storage: storage, defaults: defaults, transport: transport)
        #expect(!settings.hasKey)
        #expect(settings.activeKey() == nil)

        await settings.save("  \(Self.key)\n")
        #expect(storage.read() == Self.key)
        #expect(settings.keySuffix == "WXYZ")
        #expect(settings.probe == .accepted(summary: "Free plan, 3 of 100 requests used today"))
        // The first key saved turns the toggle on.
        #expect(settings.isEnabled)
        #expect(settings.activeKey() == Self.key)
        // One probe, to /status, carrying the key in its header.
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.absoluteString == "https://v3.football.api-sports.io/status")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "x-apisports-key") == Self.key)

        // A new launch reads it back from storage.
        let relaunched = ApiFootballSettings(storage: storage, defaults: defaults, transport: transport)
        #expect(relaunched.keySuffix == "WXYZ")
        #expect(relaunched.isEnabled)
        #expect(relaunched.activeKey() == Self.key)

        relaunched.clear()
        #expect(storage.read() == nil)
        #expect(!relaunched.hasKey)
        #expect(!relaunched.isEnabled)
        #expect(relaunched.activeKey() == nil)
    }

    @Test("The key never lands in UserDefaults: only the toggle does")
    func defaultsHoldNoKey() async throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ApiFootballSettings(
            storage: InMemorySecretStorage(),
            defaults: defaults,
            transport: probeTransport("apifootball_status_ok")
        )
        await settings.save(Self.key)
        settings.isEnabled = false
        settings.isEnabled = true

        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(stored.keys) == [ApiFootballSettings.enabledKey])
        for value in stored.values {
            #expect(!"\(value)".contains(Self.key))
            #expect(!"\(value)".contains("WXYZ"))
        }
    }

    @Test("A refused key is not saved, and the message never shows it")
    func rejectedKey() async throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = InMemorySecretStorage()
        let settings = ApiFootballSettings(
            storage: storage,
            defaults: defaults,
            transport: probeTransport("apifootball_status_bad_key")
        )

        await settings.save(Self.key)
        #expect(storage.read() == nil)
        #expect(!settings.hasKey)
        #expect(!settings.isEnabled)
        guard case .failed(let message) = settings.probe else {
            Issue.record("Expected a failure, got \(settings.probe)")
            return
        }
        #expect(message.contains("Missing application key"))
        #expect(!message.contains(Self.key))
    }

    @Test("Offline, the key is not saved")
    func offlineProbe() async throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = InMemorySecretStorage()
        let settings = ApiFootballSettings(
            storage: storage,
            defaults: defaults,
            transport: RecordingTransport(always: .status(503))
        )
        await settings.save(Self.key)
        #expect(storage.read() == nil)
        guard case .failed = settings.probe else {
            Issue.record("Expected a failure, got \(settings.probe)")
            return
        }
    }

    @Test("Replacing a key leaves the reader's toggle as it was")
    func replacingKeepsToggle() async throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = InMemorySecretStorage()
        let settings = ApiFootballSettings(
            storage: storage,
            defaults: defaults,
            transport: probeTransport("apifootball_status_ok")
        )
        await settings.save(Self.key)
        settings.isEnabled = false

        await settings.save("ffffffffffffffffffffffffffff1234")
        #expect(storage.read() == "ffffffffffffffffffffffffffff1234")
        #expect(settings.keySuffix == "1234")
        #expect(!settings.isEnabled)
        #expect(settings.activeKey() == nil)
    }
}
