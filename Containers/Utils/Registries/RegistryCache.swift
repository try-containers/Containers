//
//  RegistryCache.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

/// Holds a registry's answers for as long as they can be called current.
///
/// Registry lookups outlive the client that made them: ``Registry/client``
/// hands out a fresh value on every access, so anything worth keeping has to be
/// held `static` on the client rather than in it.
///
/// Key entries by whatever identifies a lookup for that registry. A list the
/// registry only has one of — what is trending, say — needs no key, and both
/// calls can be made without one.
actor RegistryCache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let stored: ContinuousClock.Instant
    }

    private let ttl: Duration
    private let limit: Int

    private var entries: [String: Entry] = [:]

    init(ttl: Duration = .seconds(30 * 60), limit: Int = 32) {
        self.ttl = ttl
        self.limit = limit
    }

    func value(for key: String = "") -> Value? {
        guard let entry = entries[key],
            entry.stored.duration(to: ContinuousClock.now) < ttl
        else {
            return nil
        }

        return entry.value
    }

    func store(_ value: Value, for key: String = "") {
        entries[key] = Entry(value: value, stored: ContinuousClock.now)

        guard entries.count > limit else {
            return
        }

        // Drop what has already expired, and only if that was not enough,
        // the oldest of what is left.
        let now = ContinuousClock.now
        entries = entries.filter { $0.value.stored.duration(to: now) < ttl }

        guard entries.count > limit else {
            return
        }

        let excess =
            entries
            .sorted { $0.value.stored < $1.value.stored }
            .prefix(entries.count - limit)

        for entry in excess {
            entries[entry.key] = nil
        }
    }

    func removeAll() {
        entries.removeAll()
    }
}
