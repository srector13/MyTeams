//
//  FeedCache.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "feedcache")

/// The last good JSON body of each feed, on disk, so a page opened offline
/// shows what it last loaded rather than an error (R-4).
///
/// One file per request URL under `SharedPaths.caches/FeedCache`, shared by
/// the app and the widget. The folder is held to `capacity` bytes, evicting
/// the least recently used entry first — a file's modification date is its
/// "last used", touched on every hit, so both processes keep the same order.
/// An entry older than `lifetime` is never served: two-week-old scores are
/// worse than an honest "couldn't load".
///
/// `HTTPClient` reads and writes it under a `FeedCachePolicy`; nothing else
/// needs to.
actor FeedCache {
    /// The cache the app's and the widget's `HTTPClient.shared` use.
    static let shared = FeedCache(directory: SharedPaths.caches.appending(path: "FeedCache", directoryHint: .isDirectory))

    /// The folder's size cap: 20 MB.
    static let defaultCapacity = 20 * 1024 * 1024

    /// How long a stored body may be served: 14 days.
    static let defaultLifetime: TimeInterval = 14 * 24 * 60 * 60

    /// A stored body and when it was fetched from the network.
    struct Entry: Sendable, Equatable {
        let body: Data
        let fetchedAt: Date
    }

    /// The on-disk form of an entry. The URL is kept so a file can be told
    /// apart from a hash collision.
    private struct Record: Codable {
        let url: String
        let fetchedAt: Date
        let body: Data
    }

    let directory: URL
    let capacity: Int
    let lifetime: TimeInterval
    private let clock: @Sendable () -> Date

    init(
        directory: URL,
        capacity: Int = FeedCache.defaultCapacity,
        lifetime: TimeInterval = FeedCache.defaultLifetime,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.capacity = capacity
        self.lifetime = lifetime
        self.clock = clock
    }

    /// The stored body for `url`, when there is one fetched within
    /// `lifetime` — and within `maxAge`, when given. A hit counts as a use
    /// for eviction; an expired entry is deleted.
    func read(_ url: URL, maxAge: TimeInterval? = nil) -> Entry? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file),
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.url == url.absoluteString
        else { return nil }

        let now = clock()
        let age = now.timeIntervalSince(record.fetchedAt)
        if age > lifetime {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        if let maxAge, age > maxAge {
            return nil
        }
        touch(file, at: now)
        return Entry(body: record.body, fetchedAt: record.fetchedAt)
    }

    /// Stores `body` as `url`'s latest good response, fetched now, then
    /// evicts least recently used entries until the folder fits `capacity`.
    func write(_ body: Data, for url: URL) {
        let now = clock()
        let record = Record(url: url.absoluteString, fetchedAt: now, body: body)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(record), data.count <= capacity else { return }

        let file = fileURL(for: url)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Couldn't store a feed: \(error.localizedDescription)")
            return
        }
        touch(file, at: now)
        evict()
    }

    /// Deletes least recently used entries until the folder fits `capacity`.
    private func evict() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }

        var entries = files.map { file in
            let values = try? file.resourceValues(forKeys: Set(keys))
            return (file: file, used: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > capacity else { return }

        entries.sort { $0.used < $1.used }
        for entry in entries where total > capacity {
            try? FileManager.default.removeItem(at: entry.file)
            total -= entry.size
        }
    }

    /// Marks `file` used at `date`, the eviction order's clock.
    private func touch(_ file: URL, at date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
    }

    /// `url`'s file: the SHA-256 of the URL, so any URL makes a safe name.
    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).plist", directoryHint: .notDirectory)
    }
}
