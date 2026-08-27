//
//  RecentLocations.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import Foundation

/// The places already picked through an open panel, kept as security-scoped
/// bookmarks.
enum RecentLocations {
    enum Kind: String {
        case tarArchive
        case mountSource
    }

    static let limit = 8

    static func urls(for kind: Kind) -> [URL] {
        var urls: [URL] = []
        var kept: [Data] = []

        for data in stored(for: kind) {
            guard let resolved = resolve(data) else { continue }

            urls.append(resolved.url)
            kept.append(resolved.isStale ? renew(resolved.url) ?? data : data)
        }

        if kept != stored(for: kind) {
            UserDefaults.standard.set(kept, forKey: key(for: kind))
        }

        return urls
    }

    static func remember(_ url: URL, for kind: Kind) {
        guard let data = renew(url) else { return }

        var bookmarks = stored(for: kind).filter { existing in
            resolve(existing)?.url.standardizedFileURL != url.standardizedFileURL
        }

        bookmarks.insert(data, at: 0)

        UserDefaults.standard.set(
            Array(bookmarks.prefix(limit)),
            forKey: key(for: kind)
        )
    }

    private static func key(for kind: Kind) -> String {
        "recentLocations.\(kind.rawValue)"
    }

    private static func stored(for kind: Kind) -> [Data] {
        UserDefaults.standard.array(forKey: key(for: kind)) as? [Data] ?? []
    }

    private static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false

        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            // A bookmark that no longer resolves is dropped rather than kept
            // around to fail again.
            return nil
        }

        return (url, isStale)
    }

    private static func renew(_ url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
