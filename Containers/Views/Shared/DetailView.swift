//
//  DetailView.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import AppKit
import SwiftUI

struct DetailAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let help: String
    let isEnabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        id: String,
        title: String,
        icon: String,
        help: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.help = help ?? title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// Sizes the window to each tab's natural content height. Switching tabs runs
/// four steps in order: hide the content, load the new tab, resize the window,
/// show the content.
///
/// Use `.windowResizability(.contentMinSize)` on the enclosing scene: this view
/// owns the window height, and `.contentSize` would clamp the intermediate
/// frames of the resize animation and flatten it back to a snap.
struct DetailView<
    Tab: Hashable & CaseIterable,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private var defaultMinWidth: CGFloat { 550 }
    private var maximumWidth: CGFloat { 900 }
    private let fadeDuration: TimeInterval = 0.1
    private let resizeDuration: TimeInterval = 0.18

    let showTabs: Bool
    let actions: [DetailAction]

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabIcon: (Tab) -> String
    let tabWidth: (Tab) -> CGFloat?
    /// An upper bound on a tab's height. nil lets the tab grow as tall as its
    /// content. A tab whose content can exceed its bound should provide its own
    /// ScrollView — the bound clips, it does not scroll.
    let tabMaxHeight: (Tab) -> CGFloat?
    let tabContent: (Tab) -> Content

    /// The tab whose content is currently rendered (lags selectedTab during transition).
    @State private var displayedTab: Tab
    @State private var contentOpacity: Double = 1
    @State private var measuredHeight: CGFloat = 0
    /// The most recently requested tab, consumed by the running transition.
    /// Rapid switches overwrite it, so only the last one is ever shown.
    @State private var pendingTab: Tab?
    @State private var isTransitioning = false
    @State private var hasSized = false
    @State private var resizer = WindowResizer()
    @State private var transition: Task<Void, Never>?

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        actions: [DetailAction] = [],
        tabTitle: @escaping (Tab) -> String,
        tabIcon: @escaping (Tab) -> String,
        tabWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabMaxHeight: @escaping (Tab) -> CGFloat? = { _ in nil },
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self._selectedTab = selectedTab
        self._displayedTab = State(initialValue: selectedTab.wrappedValue)
        self.showTabs = showTabs
        self.actions = actions
        self.tabTitle = tabTitle
        self.tabIcon = tabIcon
        self.tabWidth = tabWidth
        self.tabMaxHeight = tabMaxHeight
        self.tabContent = tabContent
    }

    /// Read from displayedTab, not selectedTab, so width and height change at
    /// the same moment.
    private var effectiveMinWidth: CGFloat {
        tabWidth(displayedTab) ?? defaultMinWidth
    }

    /// `fixedSize` makes the content report its ideal height instead of taking
    /// the height it is offered, so the measurement below is a property of the
    /// content alone and cannot be affected by the window height derived from
    /// it. The original `(min, max)` tab height broke exactly this: a flexible
    /// frame reports whatever it was given, so every resize changed the next
    /// reading.
    private var sizedContent: some View {
        tabContent(displayedTab)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: tabMaxHeight(displayedTab))
            .clipped()
            // After the frame, so the reading is already clamped by the bound.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.height, initial: true) { _, h in
                            guard h > 0 else { return }
                            measuredHeight = h
                        }
                }
            }
    }

    var body: some View {
        // The window sizes itself from this spacer, not from the content. An
        // overlay does not report its height to its parent, so the content's
        // ideal height never reaches the window — which is the whole point.
        // A plain `frame(maxHeight:)` around the content still passes that
        // ideal up, and SwiftUI then grew the window to fit the new tab the
        // instant it was installed, leaving the animator nothing to animate:
        // growing snapped, and only shrinking animated.
        //
        // Width is set here rather than on the content for the same reason,
        // so the window still tracks the width the tab asks for.
        Color.clear
            .frame(minWidth: effectiveMinWidth, maxWidth: maximumWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                sizedContent
                    .opacity(contentOpacity)
            }
            // Outermost, so it covers the full window while it is taller than
            // the content mid-animation, and never fades with the content.
            .background(.windowBackground)
            .clipped()
            .background(WindowBinder(resizer: resizer))
            .toolbar {
                if showTabs {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("", selection: $selectedTab) {
                            ForEach(Array(Tab.allCases), id: \.self) { tab in
                                Label(
                                    tabTitle(tab),
                                    systemImage: tabIcon(tab)
                                )
                                .tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    ForEach(actions) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            action.action()
                        } label: {
                            Label(action.title, systemImage: action.icon)
                        }
                        .disabled(!action.isEnabled)
                        .help(action.help)
                    }
                }
            }
            .toolbarBackground(.visible, for: .windowToolbar)
            .onChange(of: measuredHeight) { _, height in
                // The displayed tab changed height on its own — content
                // finished loading, a row expanded. A transition does its own
                // resizing in sequence, so stay out of its way.
                guard !isTransitioning, height > 0 else { return }

                // The first measurement is the initial sizing: apply it flat,
                // so the window opens at the right height instead of growing
                // into it.
                let duration = hasSized ? resizeDuration : 0
                hasSized = true
                Task { await resizer.fit(height: height, duration: duration) }
            }
            .onChange(of: selectedTab) { _, tab in
                pendingTab = tab
                // A transition already in flight will pick this up rather than
                // being torn down. Cancelling mid-animation is what left the
                // window locked to a stale height.
                guard !isTransitioning else { return }
                transition = Task { await runTransitions() }
            }
    }

    /// Drains `pendingTab` until the displayed tab matches what was last
    /// requested. Switching again mid-transition queues rather than restarts,
    /// so each step still runs to completion in order.
    private func runTransitions() async {
        isTransitioning = true
        defer { isTransitioning = false }

        while pendingTab != nil {
            // 1. Hide the current content.
            await fade(to: 0)

            // Re-read after the fade so a tab picked during it is honoured
            // here, instead of being shown and then immediately replaced.
            guard let tab = pendingTab else { break }
            pendingTab = nil

            // 2. Load the new tab.
            if tab != displayedTab {
                displayedTab = tab
                await settleLayout()
            }

            // Yet another tab was picked. Animating to a size that will never
            // be revealed is what makes rapid switching lurch, so drop this
            // step and the reveal below and go straight to the newer tab.
            guard pendingTab == nil else { continue }

            // 3. Resize the window, under hidden content.
            await resizer.fit(height: measuredHeight, duration: resizeDuration)
            guard pendingTab == nil else { continue }

            // 4. Show the new content, at the new size.
            await fade(to: 1)
        }

        // Never leave the content invisible, whichever branch ended the loop.
        await fade(to: 1)
    }

    /// Waits for SwiftUI to install the new tab and for the GeometryReader to
    /// report its height, so the resize that follows targets the incoming
    /// content rather than the outgoing tab's height.
    private func settleLayout() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
    }

    private func fade(to opacity: Double) async {
        // withAnimation sets the state immediately and only the rendered value
        // interpolates, so an unguarded call to the value it already holds
        // would report completion while the pixels are still moving.
        guard contentOpacity != opacity else { return }

        await withCheckedContinuation { continuation in
            withAnimation(.easeInOut(duration: fadeDuration)) {
                contentOpacity = opacity
            } completion: {
                continuation.resume()
            }
        }
    }
}

/// Animates the window to a given content height — the one step SwiftUI has no
/// hook for.
@MainActor
private final class WindowResizer {
    private weak var window: NSWindow?
    /// Height of the most recent request, applied or not. Also identifies which
    /// request owns the height lock.
    private var requestedHeight: CGFloat?

    /// The first measurement can land before the view has a window, so a
    /// request made that early is replayed here rather than dropped — that gap
    /// is what left the window opening at SwiftUI's default height.
    func bind(to window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window

        if let height = requestedHeight {
            Task { await fit(height: height, duration: 0) }
        }
    }

    /// Returns once the window has settled at `height`. A zero duration applies
    /// the frame without animating.
    func fit(height: CGFloat, duration: TimeInterval) async {
        guard height > 0 else { return }
        requestedHeight = height

        guard let window, let contentView = window.contentView else { return }

        // Force a layout pass so a measurement scheduled for the content that
        // was just installed has landed before the frame is derived from it.
        contentView.layoutSubtreeIfNeeded()

        // Convert through the window rather than subtracting contentView from
        // frame: those disagree while an earlier resize is still animating.
        var contentRect = window.contentRect(forFrameRect: window.frame)

        // The content rect spans the whole frame, including the strip the
        // toolbar draws over; only contentLayoutRect is left for the view. The
        // measured height is the view's, so it has to be grown by that chrome —
        // targeting it directly clipped every tab by the toolbar's height.
        let chrome = contentRect.height - window.contentLayoutRect.height
        let target = height + chrome

        guard abs(contentRect.height - target) > 0.5 else {
            // Already the right size, but the lock may still be a stale tab's.
            lockHeight(target, on: window)
            return
        }

        contentRect.size.height = target
        var frame = window.frameRect(forContentRect: contentRect)
        // Keep the title bar where it is; grow and shrink downward.
        frame.origin.y = window.frame.maxY - frame.height

        // Vertical resizing is locked to the content height between
        // transitions, so unlock before animating or the clamp fights every
        // intermediate frame.
        window.contentMinSize.height = 0
        window.contentMaxSize.height = .greatestFiniteMagnitude

        guard window.isVisible, duration > 0 else {
            window.setFrame(frame, display: false)
            lockHeight(target, on: window)
            return
        }

        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    // Starting a newer frame animation aborts this one and
                    // fires this handler early. Locking here would clamp the
                    // window to a height that request is animating away from.
                    if self.requestedHeight == height {
                        self.lockHeight(target, on: window)
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func lockHeight(_ height: CGFloat, on window: NSWindow) {
        window.contentMinSize.height = height
        window.contentMaxSize.height = height
    }
}

private struct WindowBinder: NSViewRepresentable {
    let resizer: WindowResizer

    func makeNSView(context: Context) -> NSView {
        BindingView(resizer: resizer)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Binds on `viewDidMoveToWindow` rather than in `updateNSView`, which can
    /// run before the view has a window and never again after.
    private final class BindingView: NSView {
        let resizer: WindowResizer

        init(resizer: WindowResizer) {
            self.resizer = resizer
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) unavailable")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated { resizer.bind(to: window) }
        }
    }
}
