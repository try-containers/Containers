//
//  DetailToolbar.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Builds the detail window's toolbar in AppKit, for one reason: the tabs have
/// to be an `NSToolbarItemGroup`, the only thing that keeps a label per entry
/// while rendering as one control. SwiftUI's `.toolbar` flattens a
/// `ToolbarItemGroup` into separate items however it is declared.
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
    private static let displayModeKey = "detailToolbarDisplayMode"

    private static var savedDisplayMode: NSToolbar.DisplayMode? {
        let raw = UserDefaults.standard.object(forKey: displayModeKey)
        guard let raw = raw as? UInt else { return nil }
        let mode = NSToolbar.DisplayMode(rawValue: raw)
        return mode == .default ? nil : mode
    }

    private weak var window: NSWindow?
    private var displayModeObservation: NSKeyValueObservation?
    private var isRebuildingTabs = false
    private var hasSettled = false
    private var builtShowingLabels: Bool?
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

        // Nothing tells SwiftUI when the user changes the display mode, and
        // the labels drawn beneath a segment are usually wider than its icon.
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

    /// Returns once the toolbar is installed and has stopped resizing itself.
    ///
    /// A window's chrome is its title bar plus its toolbar, and the toolbar
    /// lands a turn after the view appears. Sizing before that measures the
    /// title bar alone and leaves the window short by the toolbar's height, so
    /// whoever sizes it waits here first — bounded, since a toolbar that never
    /// arrives should cost a beat rather than the content.
    func whenSettled(timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !hasSettled, ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Rebuilds the tabs so AppKit measures them again: assigning new images
    /// in place does not resize an item already laid out. Deferred and guarded,
    /// because changing items makes AppKit report the display mode again, which
    /// lands straight back here.
    private func scheduleTabRebuild() {
        guard !isRebuildingTabs, builtShowingLabels != showsLabels else {
            // At its final height, so the window's chrome is worth measuring.
            if !isRebuildingTabs { hasSettled = true }
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

    /// The group has no view of its own, so a tab is only ever as wide as its
    /// image. Padding it is the width.
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
            // The caption alone; the toolbar adds its own padding.
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
                // In place, not a rebuild: a run button that becomes a stop
                // button is the same item with a different face.
                if item.label != action.title {
                    item.label = action.title
                    item.toolTip = action.help
                    item.image = NSImage(
                        systemSymbolName: action.icon,
                        accessibilityDescription: action.title
                    )
                }
                item.isEnabled = action.isEnabled
            }
        }
    }

    /// The identifiers the toolbar is made of. State that only changes an
    /// item — enabled, selected — is applied in place instead.
    private var shape: [String] {
        tabs.map(\.title) + ["·"] + actions.map(\.id)
    }

    /// Unanimated: a toolbar animates items in and out, and the first build
    /// lands while the window is still opening — the items would fade in a
    /// beat after the title rather than being there with it.
    private func rebuild(_ toolbar: NSToolbar) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0

            while !toolbar.items.isEmpty {
                toolbar.removeItem(at: toolbar.items.count - 1)
            }

            for (index, identifier) in identifiers.enumerated() {
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
            }
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
        group.visibilityPriority = .high
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

/// Installs the toolbar as soon as the window exists, before the detail it
/// belongs to has loaded. Declared on the window rather than inside the view
/// that fills it: a toolbar arriving later changes the window's chrome, and
/// so the height everything else is sized against.
struct DetailToolbarAttacher: NSViewRepresentable {
    let controller: DetailToolbarController
    let tabs: [DetailToolbarController.Tab]
    let actions: [DetailAction]

    func makeNSView(context: Context) -> NSView {
        controller.tabs = tabs
        controller.actions = actions
        return DetailToolbarBinder.BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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

    final class BindingView: NSView {
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

            // Before the window is on screen there is no render pass to
            // reenter, and installing here means the toolbar is up before the
            // window is shown rather than arriving a beat after the title bar.
            guard window.isVisible else {
                controller.attach(to: window)
                controller.update()
                return
            }

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
