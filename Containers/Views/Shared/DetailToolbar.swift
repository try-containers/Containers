//
//  DetailToolbar.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Builds the detail window's toolbar in AppKit, for one reason: the tabs have
/// to be an `NSToolbarItemGroup`. A toolbar draws its Icon and Text label per
/// item, and only a group keeps a label per entry while still rendering as one
/// control. SwiftUI's `.toolbar` flattens `ToolbarItemGroup` into separate
/// items, so the tabs come out as separate buttons however they are declared.
@MainActor
final class DetailToolbarController: NSObject, NSToolbarDelegate {
    struct Tab: Equatable {
        let title: String
        let icon: String
    }

    var tabs: [Tab] = []
    var selectedIndex = 0
    var actions: [DetailAction] = []
    var onSelectTab: (Int) -> Void = { _ in }

    private static let tabsIdentifier = NSToolbarItem.Identifier("tabs")
    /// Shared by every detail window, so the choice is made once. Stored here
    /// rather than through `autosavesConfiguration`, which would also restore
    /// item identifiers — and the three detail windows have different actions
    /// under the one toolbar identifier.
    private static let displayModeKey = "detailToolbarDisplayMode"

    private static var savedDisplayMode: NSToolbar.DisplayMode? {
        let raw = UserDefaults.standard.object(forKey: displayModeKey)
        guard let raw = raw as? UInt else { return nil }
        let mode = NSToolbar.DisplayMode(rawValue: raw)
        // `.default` is the toolbar's own fallback, which earlier builds
        // persisted before there was a default here. It is not a choice.
        return mode == .default ? nil : mode
    }

    private weak var window: NSWindow?
    private var displayModeObservation: NSKeyValueObservation?
    private var isRebuildingTabs = false
    /// What the tabs were last built for, so a repeat report of the same
    /// display mode does not rebuild them again.
    private var builtShowingLabels: Bool?
    /// What the toolbar was last built from; a change means new items rather
    /// than new state on the existing ones.
    private var builtFrom: [String] = []

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        let toolbar = NSToolbar(identifier: "detail")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = Self.savedDisplayMode ?? .iconOnly
        builtFrom = shape

        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // The segments are sized to their icons; the labels are drawn beneath
        // by the toolbar and are usually wider. Nothing tells SwiftUI when the
        // user changes the display mode, so watch the toolbar itself.
        displayModeObservation = toolbar.observe(
            \.displayMode,
            options: [.initial, .new]
        ) { toolbar, _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(
                    toolbar.displayMode.rawValue,
                    forKey: Self.displayModeKey
                )
                self.scheduleTabRebuild()
            }
        }
    }

    /// Rebuilds the tabs so AppKit measures them again. Assigning new images
    /// in place does not resize an item that has already been laid out, so a
    /// tab kept its caption width after the captions were hidden.
    ///
    /// Deferred and guarded: changing the toolbar's items makes AppKit report
    /// the display mode again, which lands straight back here.
    private func scheduleTabRebuild() {
        guard !isRebuildingTabs, builtShowingLabels != showsLabels else {
            return
        }

        isRebuildingTabs = true

        Task { @MainActor in
            rebuildTabs()
            isRebuildingTabs = false

            // The mode can change again while a rebuild is pending.
            scheduleTabRebuild()
        }
    }

    private func rebuildTabs() {
        builtShowingLabels = showsLabels

        guard
            let toolbar = window?.toolbar,
            let index = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == Self.tabsIdentifier
            })
        else { return }

        toolbar.removeItem(at: index)
        toolbar.insertItem(withItemIdentifier: Self.tabsIdentifier, at: index)
    }

    private var showsLabels: Bool {
        switch window?.toolbar?.displayMode {
        case .iconAndLabel, .labelOnly: true
        default: false
        }
    }

    /// The group has no view of its own — AppKit lays the subitems out — so a
    /// tab is only ever as wide as its image. Padding it is the width.
    private var tabImages: [NSImage] {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        return tabs.map { tab in
            let image =
                NSImage(
                    systemSymbolName: tab.icon,
                    accessibilityDescription: tab.title
                ) ?? NSImage()

            guard showsLabels else { return image }

            let caption = tab.title as NSString
            let width = caption.size(withAttributes: [.font: font]).width
            // The caption alone: the toolbar adds its own padding around an
            // item, so anything on top of this reads as too wide.
            return image.widened(to: ceil(width))
        }
    }

    func update() {
        guard let toolbar = window?.toolbar else { return }

        guard builtFrom == shape else {
            builtFrom = shape
            rebuild(toolbar)
            return
        }

        for item in toolbar.items {
            if let group = item as? NSToolbarItemGroup {
                if group.selectedIndex != selectedIndex {
                    group.selectedIndex = selectedIndex
                }
            } else if let action = action(for: item.itemIdentifier) {
                item.isEnabled = action.isEnabled
            }
        }
    }

    /// The identifiers the toolbar is made of. State that only changes an
    /// item — enabled, selected — is applied in place instead.
    private var shape: [String] {
        tabs.map(\.title) + ["·"] + actions.map(\.id)
    }

    private func rebuild(_ toolbar: NSToolbar) {
        while !toolbar.items.isEmpty {
            toolbar.removeItem(at: toolbar.items.count - 1)
        }

        for (index, identifier) in identifiers.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        var result: [NSToolbarItem.Identifier] = []

        if !tabs.isEmpty {
            result.append(Self.tabsIdentifier)
            result.append(.flexibleSpace)
        }

        result += actions.map { NSToolbarItem.Identifier($0.id) }

        return result
    }

    private func action(for identifier: NSToolbarItem.Identifier) -> DetailAction? {
        actions.first { $0.id == identifier.rawValue }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.tabsIdentifier {
            return tabGroup(itemIdentifier)
        }

        guard let action = action(for: itemIdentifier) else { return nil }
        return actionItem(itemIdentifier, action: action)
    }

    private func tabGroup(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: tabImages,
            selectionMode: .selectOne,
            labels: tabs.map(\.title),
            target: self,
            action: #selector(tabSelected)
        )
        group.selectedIndex = selectedIndex
        // The tabs are how the window is navigated, so they outrank the
        // actions when the toolbar runs out of room and starts moving items
        // into the overflow menu.
        group.visibilityPriority = .high
        // And they stay as three tabs rather than folding into the single
        // popup a narrow toolbar would otherwise reduce them to.
        group.controlRepresentation = .expanded
        return group
    }

    private func actionItem(
        _ identifier: NSToolbarItem.Identifier,
        action: DetailAction
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = action.title
        item.paletteLabel = action.title
        item.toolTip = action.help
        item.image = NSImage(
            systemSymbolName: action.icon,
            accessibilityDescription: action.title
        )
        item.isBordered = true
        // Managed from SwiftUI's state, so keep AppKit from overriding it with
        // a responder-chain check that would always fail here.
        item.autovalidates = false
        item.isEnabled = action.isEnabled
        item.target = self
        item.action = #selector(actionInvoked)

        if action.isDestructive {
            item.image = item.image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            )
        }

        return item
    }

    @objc private func tabSelected(_ sender: NSToolbarItemGroup) {
        onSelectTab(sender.selectedIndex)
    }

    @objc private func actionInvoked(_ sender: NSToolbarItem) {
        action(for: sender.itemIdentifier)?.action()
    }
}

/// Hands the controller its window, and the current state on every update.
struct DetailToolbarBinder: NSViewRepresentable {
    let controller: DetailToolbarController
    let tabs: [DetailToolbarController.Tab]
    let selectedIndex: Int
    let actions: [DetailAction]
    let onSelectTab: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.tabs = tabs
        controller.selectedIndex = selectedIndex
        controller.actions = actions
        controller.onSelectTab = onSelectTab
        controller.update()
    }

    private final class BindingView: NSView {
        let controller: DetailToolbarController

        init(controller: DetailToolbarController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            // Deferred: this runs inside the render pass that installing a
            // toolbar would reenter.
            Task { @MainActor in
                controller.attach(to: window)
                controller.update()
            }
        }
    }
}

extension NSImage {
    /// The same symbol on a wider canvas, so a toolbar item that is sized to
    /// its image can be made to fit the label drawn under it.
    fileprivate func widened(to width: CGFloat) -> NSImage {
        guard width > size.width else { return self }

        let padded = NSImage(
            size: NSSize(width: width, height: size.height),
            flipped: false
        ) { [self] bounds in
            draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: 0),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }

        padded.isTemplate = isTemplate
        return padded
    }
}
