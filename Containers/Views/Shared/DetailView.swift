//
//  DetailView.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import AppKit
import SwiftUI
import TipKit

struct DetailAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let help: String
    let isEnabled: Bool
    let isDestructive: Bool
    let tip: AnyTip?
    let action: () -> Void

    init(
        id: String,
        title: String,
        icon: String,
        help: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        tip: AnyTip? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.help = help ?? title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.tip = tip
        self.action = action
    }
}

/// The size a detail window opens at, and the smallest it ever gets.
enum DetailPlaceholder {
    static let width: CGFloat = 550
    static let height: CGFloat = 140

    /// Opens the window over the middle of whichever window the user opened it
    /// from. Restoration used to carry that placement, and disabling it — so a
    /// new window does not inherit the last one's height — took the placement
    /// with it.
    ///
    /// The parent is measured in AppKit's screen coordinates, which run upward
    /// from the bottom, and applied as an offset from the middle of `display`,
    /// which runs downward.
    static func centred(on display: CGRect) -> WindowPlacement {
        let size = CGSize(width: width, height: height)

        guard
            let parent = NSApp.keyWindow,
            let screen = parent.screen
        else {
            return WindowPlacement(.center, size: size)
        }

        let offsetX = parent.frame.midX - screen.frame.midX
        let offsetY = screen.frame.midY - parent.frame.midY

        return WindowPlacement(
            CGPoint(
                x: display.midX + offsetX - size.width / 2,
                y: display.midY + offsetY - size.height / 2
            ),
            size: size
        )
    }
}

/// Sizes the window to each tab's content height: hide, load, resize, show.
/// The load step waits on `contentReady`, so a tab that fetches its own
/// data holds the window where it is until there is something to size to.
///
/// Requires `.windowResizability(.contentMinSize)` on the enclosing scene:
/// `.contentSize` clamps the resize animation's intermediate frames.
struct DetailView<
    Tab: Hashable & CaseIterable,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private var defaultMinWidth: CGFloat { DetailPlaceholder.width }
    private var maximumWidth: CGFloat { 900 }
    private var minimumHeight: CGFloat { DetailPlaceholder.height }
    private var maximumHeight: CGFloat {
        guard let visible = resizer.visibleScreenHeight else { return 720 }
        return max(minimumHeight, visible - 160)
    }
    private let fadeDuration: TimeInterval = 0.1
    private let resizeDuration: TimeInterval = 0.18
    private let readyTimeout: Duration = .seconds(2)

    let showTabs: Bool
    let actions: [DetailAction]

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabIcon: (Tab) -> String
    let tabWidth: (Tab) -> CGFloat?
    /// Bounds the fit only; content always fills the window, so a tab that can
    /// outgrow its bound needs its own ScrollView.
    let tabMaxHeight: (Tab) -> CGFloat?
    /// Caps the content and centres it, so a tab holds its shape in a window
    /// left wider by another tab. `nil` runs edge to edge.
    let tabContentWidth: (Tab) -> CGFloat?
    let tabContent: (Tab) -> Content

    @State private var displayedTab: Tab
    @State private var contentOpacity: Double = 0
    @State private var measuredHeight: CGFloat = 0
    @State private var contentOverflows = false
    @State private var pendingTab: Tab?
    @State private var isTransitioning = false
    @State private var hasSized = false
    @State private var needsRefit = false
    @State private var hasMeasured = false
    @State private var resizer = WindowResizer()
    @State private var toolbarController = DetailToolbarController()

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        actions: [DetailAction] = [],
        tabTitle: @escaping (Tab) -> String,
        tabIcon: @escaping (Tab) -> String,
        tabWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabMaxHeight: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabContentWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
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
        self.tabContentWidth = tabContentWidth
        self.tabContent = tabContent
    }

    private var effectiveMinWidth: CGFloat {
        tabWidth(displayedTab) ?? defaultMinWidth
    }

    private var heightCap: CGFloat {
        min(tabMaxHeight(displayedTab) ?? maximumHeight, maximumHeight)
    }

    private var toolbarTabs: [DetailToolbarController.Tab] {
        Array(Tab.allCases).map {
            .init(title: tabTitle($0), icon: tabIcon($0))
        }
    }

    private var sizedContent: some View {
        FillingContent(onIdealHeight: fitTo) {
            tabContent(displayedTab)
                // The cap first, then the full width to centre it in. Measuring
                // happens through both, so the height reported is the height at
                // the width the content is actually drawn at.
                .frame(maxWidth: tabContentWidth(displayedTab) ?? .infinity)
                .frame(maxWidth: .infinity)
        }
    }

    private func fitTo(idealHeight: CGFloat) {
        // Zero from a tab that declares a bound is unbounded content, not empty
        // content, so it opens at the bound and is resizable from there.
        let unbounded = idealHeight <= 0 && tabMaxHeight(displayedTab) != nil
        let ideal = unbounded ? heightCap : idealHeight
        guard ideal > 0 else { return }

        let height = min(max(ideal, minimumHeight), heightCap)
        let overflows = unbounded || ideal > height + 0.5

        // `awaitMeasurement` waits on the first report after a swap, so it
        // gets through even when it matches the outgoing height.
        guard
            !hasMeasured
                || abs(measuredHeight - height) > 0.5
                || overflows != contentOverflows
        else { return }

        // This runs from layout, so the writes are deferred.
        Task { @MainActor in
            measuredHeight = height
            contentOverflows = overflows
            hasMeasured = true
        }
    }

    var body: some View {
        // The window sizes itself from this spacer: an overlay does not report
        // its height to its parent. Passing it up instead grew the window the
        // instant a tab was installed, leaving the animator nothing to do.
        Color.clear
            .frame(minWidth: effectiveMinWidth, maxWidth: maximumWidth)
            // `.contentMinSize` derives the window's floor from this, and
            // SwiftUI overwrites a floor set directly on NSWindow.
            .frame(minHeight: minimumHeight, maxHeight: .infinity)
            .overlay(alignment: .top) {
                sizedContent
                    .opacity(contentOpacity)
            }
            .background(.windowBackground)
            .clipped()
            .background(WindowBinder(resizer: resizer))
            .background(
                DetailToolbarBinder(
                    controller: toolbarController,
                    tabs: showTabs ? toolbarTabs : [],
                    selectedIndex: Array(Tab.allCases)
                        .firstIndex(of: displayedTab) ?? 0,
                    actions: actions,
                    onSelectTab: { index in
                        let all = Array(Tab.allCases)
                        guard all.indices.contains(index) else { return }
                        selectedTab = all[index]
                    }
                )
            )
            .onChange(of: contentOverflows, initial: true) { _, overflows in
                resizer.setResizable(overflows)
            }
            .onChange(of: measuredHeight) { _, height in
                guard height > 0 else { return }

                guard hasSized else {
                    hasSized = true
                    requestTransition(to: displayedTab)
                    return
                }

                guard !isTransitioning else {
                    needsRefit = true
                    return
                }

                Task {
                    await resizer.fit(height: height, duration: resizeDuration)
                }
            }
            .onChange(of: selectedTab) { _, tab in
                requestTransition(to: tab)
            }
            .task {
                // Show the content anyway if no measurement ever arrives.
                try? await Task.sleep(for: .milliseconds(400))
                guard !hasSized else { return }
                await fade(to: 1)
            }
    }

    private func requestTransition(to tab: Tab) {
        pendingTab = tab
        // Cancelling a transition mid-animation leaves a stale height.
        guard !isTransitioning else { return }
        Task { await runTransitions() }
    }

    /// Drains `pendingTab`, so switching again queues rather than restarts.
    private func runTransitions() async {
        isTransitioning = true
        defer { isTransitioning = false }

        while pendingTab != nil || needsRefit {
            guard pendingTab != nil else {
                needsRefit = false
                await resizer.fit(
                    height: measuredHeight,
                    duration: resizeDuration
                )
                continue
            }

            await fade(to: 0)

            guard let tab = pendingTab else { break }
            pendingTab = nil

            if tab != displayedTab {
                hasMeasured = false
                displayedTab = tab
                await awaitMeasurement()
            }

            guard pendingTab == nil else { continue }

            needsRefit = false
            await resizer.fit(height: measuredHeight, duration: resizeDuration)
            guard pendingTab == nil else { continue }

            await fade(to: 1)
        }

        await fade(to: 1)
    }

    /// Waits for the newly displayed tab to report a height — for a tab that
    /// fetches its own data, the whole of the load. On timeout it carries on.
    private func awaitMeasurement() async {
        let deadline = ContinuousClock.now.advanced(by: readyTimeout)

        while !hasMeasured, ContinuousClock.now < deadline {
            guard pendingTab == nil else { return }

            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func fade(to opacity: Double) async {
        // withAnimation only interpolates the rendered value, so calling it
        // with the value already held completes while pixels are still moving.
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

/// Hands the content the height it is offered, and separately reports the
/// height it would take on its own — both from one pass over one instance, so
/// a tab's data is not loaded twice.
private struct FillingContent: Layout {
    let onIdealHeight: @MainActor @Sendable (CGFloat) -> Void

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let ideal =
            subview.isContentUnbounded
            ? CGSize(width: proposal.width ?? 0, height: 0)
            : subview.sizeThatFits(
                ProposedViewSize(width: proposal.width, height: nil)
            )

        // A nil width is SwiftUI probing for extremes; an unready tab measures
        // whatever it draws while empty.
        if proposal.width != nil, subview.isContentReady {
            MainActor.assumeIsolated { onIdealHeight(ideal.height) }
        }

        return proposal.replacingUnspecifiedDimensions(by: ideal)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(bounds.size)
        )
    }
}

/// Animates the window height — the one step SwiftUI has no hook for.
@MainActor
private final class WindowResizer {
    private weak var window: NSWindow?
    private var requestedHeight: CGFloat?
    private var requestedResizable = false

    /// Replays a request made before the view had a window. Deferred a turn:
    /// this runs inside the render pass mutating the window would reenter.
    func bind(to window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window

        Task { @MainActor in
            guard self.window === window else { return }

            apply(resizable: requestedResizable, to: window)

            if let height = requestedHeight {
                await fit(height: height, duration: 0)
            }
        }
    }

    var visibleScreenHeight: CGFloat? {
        (window?.screen ?? NSScreen.main)?.visibleFrame.height
    }

    /// Deferred a turn: the caller is an `onChange`, run as part of a view
    /// update, and the style mask rebuilds the title bar.
    func setResizable(_ resizable: Bool) {
        requestedResizable = resizable

        Task { @MainActor in
            guard let window, requestedResizable == resizable else { return }
            apply(resizable: resizable, to: window)
        }
    }

    private func apply(resizable: Bool, to window: NSWindow) {
        if resizable {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
    }

    /// Returns once the window has settled. Zero duration skips the animation.
    func fit(height: CGFloat, duration: TimeInterval) async {
        guard height > 0 else { return }
        requestedHeight = height

        guard let window else { return }

        // Convert through the window: contentView and frame disagree while an
        // earlier resize is still animating.
        var contentRect = window.contentRect(forFrameRect: window.frame)

        // Only contentLayoutRect is left for the view, so grow the measured
        // height by the strip the toolbar draws over.
        let chrome = contentRect.height - window.contentLayoutRect.height
        let target = height + chrome

        guard abs(contentRect.height - target) > 0.5 else { return }

        contentRect.size.height = target
        // Keep the title bar where it is; grow and shrink downward.
        var frame = window.frameRect(forContentRect: contentRect)
        frame.origin.y = window.frame.maxY - frame.height

        guard window.isVisible, duration > 0 else {
            window.setFrame(frame, display: false)
            return
        }

        // TODO: A web-view tab logs "NSHostingView is being laid out
        // reentrantly" once per tick of this animation: the tick lays the
        // hosting view out, a WKWebView renders continuously, so the layout
        // lands inside a render and AppKit skips that pass. Harmless — the
        // next tick redoes it — but worth an alternative. Passing duration 0
        // for tabs declaring `contentUnbounded()` silences it, at the cost of
        // the animation there.
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                continuation.resume()
            }
        }
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
