//
//  View+Content.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import SwiftUI

/// Declarations a view makes about its own height, for a `Layout` that sizes
/// itself — or its window — to that view.
///
/// Layout values rather than preferences: they are read in the same pass as the
/// height they qualify, where a preference would arrive a pass late, after the
/// content it describes had already been measured.
extension View {
    /// Declares whether this content has finished loading. Until it has, there
    /// is nothing worth measuring, and a layout reading `isContentReady` can
    /// hold the size it already had rather than fit to a half-drawn view.
    ///
    /// Apply to the outermost view being laid out: a layout value set inside a
    /// stack belongs to that stack, not to the layout above it.
    func contentReady(_ isReady: Bool) -> some View {
        layoutValue(key: ContentReadyKey.self, value: isReady)
    }

    /// Declares that this content has no height of its own — an
    /// `NSViewRepresentable` with no intrinsic size, or anything that scrolls
    /// to fill what it is given. A layout reading `isContentUnbounded` should
    /// give it a bound of its own instead of asking.
    func contentUnbounded(_ isUnbounded: Bool = true) -> some View {
        layoutValue(key: ContentUnboundedKey.self, value: isUnbounded)
    }
}

extension LayoutSubview {
    /// See `View.contentReady(_:)`. True for content that never declared it.
    nonisolated var isContentReady: Bool {
        self[ContentReadyKey.self]
    }

    /// See `View.contentUnbounded(_:)`. Asking such a subview for its ideal
    /// size is not free: SwiftUI answers for an `NSViewRepresentable` by laying
    /// out its subtree, nesting an AppKit layout inside the pass that asked.
    nonisolated var isContentUnbounded: Bool {
        self[ContentUnboundedKey.self]
    }
}

private struct ContentReadyKey: LayoutValueKey {
    nonisolated static let defaultValue = true
}

private struct ContentUnboundedKey: LayoutValueKey {
    nonisolated static let defaultValue = false
}
