//
//  DashboardToolbar.swift
//  Containers
//
//  Created by Axel Martinez on 02/08/2026.
//

import AppKit
import SwiftUI

/// Builds the dashboard window's toolbar in AppKit to allow more customization than SwiftUI.
@MainActor
final class DashboardToolbarController: NSObject, NSToolbarDelegate {
    var tabs: [String] = []
    var selectedIndex = 0
    var isEnabled = true
    var showsFilter = false
    var isFilterOn = false
    var searchText = ""
    var onSelectTab: (Int) -> Void = { _ in }
    var onToggleFilter: (Bool) -> Void = { _ in }
    var onAdd: () -> Void = {}
    var onSearch: (String) -> Void = { _ in }
    /// The tip to hang off the add button, or nil when it should not show.
    /// TipKit's `.popoverTip` needs a SwiftUI view to attach to and a toolbar
    /// item is not one, so the popover is presented here instead.
    var addTip: AnyView?

    private static let tabsIdentifier = NSToolbarItem.Identifier("tabs")
    private static let filterIdentifier = NSToolbarItem.Identifier("filter")
    private static let addIdentifier = NSToolbarItem.Identifier("add")
    private static let searchIdentifier = NSToolbarItem.Identifier("search")

    private weak var window: NSWindow?
    /// What the toolbar was last built from; a change means new items rather
    /// than new state on the existing ones.
    private var builtFrom: [String] = []
    private var tipPopover: NSPopover?

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }

        self.window = window

        let toolbar = NSToolbar(identifier: "dashboard")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [Self.tabsIdentifier]

        builtFrom = shape

        window.toolbar = toolbar
        window.toolbarStyle = .unified

        applyChrome()

        if ProcessInfo.processInfo.environment["DEBUG_FLASH"] != nil {
            @MainActor func searchWidth() -> CGFloat {
                guard let root = window.contentView?.superview else { return -1 }
                var found: CGFloat = -1

                @MainActor func walk(_ v: NSView) {
                    if String(describing: type(of: v)) == "NSSearchToolbarItemView" {
                        found = v.frame.width
                    }
                    for view in v.subviews {
                        walk(view)
                    }
                }
                walk(root)
                return found
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Task { @MainActor in
                    var samples: [String] = []
                    for _ in 0..<75 {
                        samples.append(String(format: "%.0f", searchWidth()))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    NSLog("DEBUG widths %@", samples.joined(separator: " "))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.onSelectTab(1)
                }
            }
        }
    }

    /// Hides the title, which only repeated the app name and cost the toolbar
    /// the width its centred tabs need to stay uncollapsed, and drops the
    /// divider under the toolbar — `titlebarSeparatorStyle` does nothing here,
    /// a transparent titlebar is what removes it.
    ///
    /// Reapplied from `update()` and not just `attach`, because the window
    /// setup puts the divider back once after the items are installed.
    private func applyChrome() {
        guard let window else { return }

        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }

        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
    }

    /// The identifiers the toolbar is made of. State that only changes an
    /// item — enabled, selected — is applied in place instead.
    private var shape: [String] {
        tabs + (showsFilter ? ["filter"] : []) + ["add", "search"]
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        var result: [NSToolbarItem.Identifier] = []

        if !tabs.isEmpty {
            result.append(Self.tabsIdentifier)
        }

        if showsFilter {
            result.append(Self.filterIdentifier)
        }

        result.append(Self.addIdentifier)
        result.append(.space)
        result.append(Self.searchIdentifier)

        return result
    }

    func update() {
        guard let toolbar = window?.toolbar else { return }

        applyChrome()

        guard builtFrom == shape else {
            builtFrom = shape
            rebuild(toolbar)
            return
        }

        for item in toolbar.items {
            switch item.itemIdentifier {
            case Self.tabsIdentifier:
                guard let group = item as? NSToolbarItemGroup else { break }
                if group.selectedIndex != selectedIndex {
                    group.selectedIndex = selectedIndex
                }
            case Self.filterIdentifier:
                guard let group = item as? NSToolbarItemGroup else { break }
                if group.isSelected(at: 0) != isFilterOn {
                    group.setSelected(isFilterOn, at: 0)
                }
            case Self.searchIdentifier:
                guard let search = item as? NSSearchToolbarItem else { break }
                if search.searchField.stringValue != searchText {
                    search.searchField.stringValue = searchText
                }
            default:
                break
            }

            item.isEnabled = isEnabled
        }

        syncTipPopover()
    }

    private func syncTipPopover() {
        guard let addTip else {
            tipPopover?.close()
            tipPopover = nil
            return
        }

        guard tipPopover == nil, let anchor = addButtonView else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: addTip.frame(width: 260)
        )
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        tipPopover = popover
    }

    /// The add button's item viewer, found by the label AppKit publishes for
    /// it — a standard `NSToolbarItem` builds its own view and does not hand it
    /// back through `view`.
    private var addButtonView: NSView? {
        guard let root = window?.contentView?.superview else { return nil }

        func walk(_ view: NSView) -> NSView? {
            if view.accessibilityRole() == .button,
                view.accessibilityLabel() == "New"
            {
                return view
            }

            for subview in view.subviews {
                if let found = walk(subview) { return found }
            }

            return nil
        }

        return walk(root)
    }

    /// Only the items that actually differ. Emptying the toolbar and refilling
    /// it takes the search field down with it, and the replacement comes back
    /// collapsed for a frame — a magnifier flickering on every switch to a tab
    /// whose buttons differ.
    private func rebuild(_ toolbar: NSToolbar) {
        let wanted = identifiers

        for (index, item) in toolbar.items.enumerated().reversed()
        where !wanted.contains(item.itemIdentifier) {
            toolbar.removeItem(at: index)
        }

        for (index, identifier) in wanted.enumerated()
        where !toolbar.items.contains(where: { $0.itemIdentifier == identifier }) {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
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
        switch itemIdentifier {
        case Self.tabsIdentifier: tabGroup(itemIdentifier)
        case Self.filterIdentifier: filterItem(itemIdentifier)
        case Self.addIdentifier: addItem(itemIdentifier)
        case Self.searchIdentifier: searchItem(itemIdentifier)
        default: nil
        }
    }

    private func tabGroup(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            titles: tabs,
            selectionMode: .selectOne,
            labels: tabs,
            target: self,
            action: #selector(tabSelected)
        )
        group.selectedIndex = selectedIndex
        group.isEnabled = isEnabled
        group.visibilityPriority = .high
        group.controlRepresentation = .expanded
        return group
    }

    /// A one-entry group rather than a plain item: `.selectAny` is what draws
    /// the on state, which a bordered `NSToolbarItem` has no way to show.
    private func filterItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let title = "Running containers only"
        let image =
            NSImage(
                systemSymbolName: "line.3.horizontal.decrease",
                accessibilityDescription: title
            ) ?? NSImage()

        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: [image],
            selectionMode: .selectAny,
            labels: [title],
            target: self,
            action: #selector(filterToggled)
        )
        group.setSelected(isFilterOn, at: 0)
        group.isEnabled = isEnabled
        group.toolTip = title
        return group
    }

    private func addItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "New"
        item.paletteLabel = "New"
        item.toolTip = "New"
        item.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New"
        )
        item.isBordered = true
        // Managed from SwiftUI's state, so keep AppKit from overriding it with
        // a responder-chain check that would always fail here.
        item.autovalidates = false
        item.isEnabled = isEnabled
        item.target = self
        item.action = #selector(addInvoked)
        return item
    }

    private func searchItem(_ identifier: NSToolbarItem.Identifier) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        item.searchField.placeholderString = "Search"
        item.searchField.delegate = self
        item.searchField.stringValue = searchText
        item.preferredWidthForSearchField = 220
        item.resignsFirstResponderWithCancel = true
        item.isEnabled = isEnabled
        return item
    }

    @objc private func tabSelected(_ sender: NSToolbarItemGroup) {
        onSelectTab(sender.selectedIndex)
    }

    @objc private func filterToggled(_ sender: NSToolbarItemGroup) {
        onToggleFilter(sender.isSelected(at: 0))
    }

    @objc private func addInvoked(_ sender: NSToolbarItem) {
        onAdd()
    }
}

extension DashboardToolbarController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        searchText = field.stringValue
        onSearch(field.stringValue)
    }
}

/// Hands the controller its window, and the current state on every update.
struct DashboardToolbarBinder: NSViewRepresentable {
    let controller: DashboardToolbarController
    let tabs: [String]
    let selectedIndex: Int
    let isEnabled: Bool
    let showsFilter: Bool
    let isFilterOn: Bool
    let searchText: String
    let onSelectTab: (Int) -> Void
    let onToggleFilter: (Bool) -> Void
    let onAdd: () -> Void
    let onSearch: (String) -> Void
    let addTip: AnyView?

    func makeNSView(context: Context) -> NSView {
        BindingView(controller: controller)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.tabs = tabs
        controller.selectedIndex = selectedIndex
        controller.isEnabled = isEnabled
        controller.showsFilter = showsFilter
        controller.isFilterOn = isFilterOn
        controller.searchText = searchText
        controller.onSelectTab = onSelectTab
        controller.onToggleFilter = onToggleFilter
        controller.onAdd = onAdd
        controller.onSearch = onSearch
        controller.addTip = addTip
        controller.update()
    }

    private final class BindingView: NSView {
        let controller: DashboardToolbarController

        init(controller: DashboardToolbarController) {
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
