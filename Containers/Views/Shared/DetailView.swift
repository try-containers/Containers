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

/// The size a detail window opens at, before it has anything to size to.
///
/// One per window, measured from what each one's overview actually settles at,
/// so opening it is not followed by a resize. They differ enough — the image
/// overview is four rows, the volume's is nine — that a shared number would be
/// wrong for all three.
enum DetailPlaceholder {
    static let container = CGSize(width: 550, height: 230)
    static let image = CGSize(width: 650, height: 158)
    static let volume = CGSize(width: 550, height: 214)

    /// The narrowest a tab may be when it does not ask for a width of its own,
    /// which is also the narrowest the placeholders are.
    static let width: CGFloat = 550
    static let minimumHeight: CGFloat = 140

    /// Centres on the window it was opened from. The parent is measured in
    /// AppKit's upward coordinates, `display` runs downward.
    static func centred(on display: CGRect, size: CGSize) -> WindowPlacement {
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

/// Sizes the window to each tab's content: hide, load, resize, show.
///
/// Requires `.windowResizability(.contentMinSize)` on the enclosing scene:
/// `.contentSize` clamps the resize animation's intermediate frames.
struct DetailView<
    Tab: Hashable & CaseIterable,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private var defaultMinWidth: CGFloat { DetailPlaceholder.width }
    private var maximumWidth: CGFloat { 900 }
    private var minimumHeight: CGFloat { DetailPlaceholder.minimumHeight }
    private var maximumHeight: CGFloat {
        guard let visible = resizer.visibleScreenHeight else { return 720 }
        return max(minimumHeight, visible - 160)
    }
    private let fadeDuration: TimeInterval = 0.1
    private let resizeDuration: TimeInterval = 0.18
    private let readyTimeout: Duration = .seconds(2)
    private let toolbarTimeout: Duration = .milliseconds(500)

    let showTabs: Bool
    let actions: [DetailAction]

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabIcon: (Tab) -> String
    let tabWidth: (Tab) -> CGFloat?
    /// Bounds the fit only; a tab that can outgrow it needs its own ScrollView.
    let tabMaxHeight: (Tab) -> CGFloat?
    /// Caps and centres the content; `nil` runs edge to edge.
    let tabContentWidth: (Tab) -> CGFloat?
    let tabContent: (Tab) -> Content
    private let injectedToolbarController: DetailToolbarController?

    @State private var displayedTab: Tab
    @State private var contentOpacity: Double = 0
    @State private var measuredHeight: CGFloat = 0
    @State private var measuredWidth: CGFloat = 0
    @State private var naturalWidth: CGFloat = 0
    @State private var heightOverflows = false
    @State private var widthOverflows = false
    @State private var pendingTab: Tab?
    @State private var isTransitioning = false
    @State private var hasSized = false
    @State private var needsRefit = false
    @State private var hasMeasured = false
    @State private var hasAwaitedToolbar = false
    @State private var resizer = WindowResizer()
    /// Used when the window supplied none. Attaching it early keeps the
    /// chrome from changing under the first fit.
    @State private var ownToolbarController = DetailToolbarController()

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        actions: [DetailAction] = [],
        tabTitle: @escaping (Tab) -> String,
        tabIcon: @escaping (Tab) -> String,
        tabWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabMaxHeight: @escaping (Tab) -> CGFloat? = { _ in nil },
        tabContentWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        toolbarController: DetailToolbarController? = nil,
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self.injectedToolbarController = toolbarController
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

    /// How wide a drag may take the window, as opposed to how wide it opens.
    /// Content that is cut off should be draggable until it is not, and the
    /// opening cap is far narrower than that — height works the same way,
    /// opening at its cap but free to be dragged to the screen.
    private var dragMaximumWidth: CGFloat {
        guard widthOverflows else { return maximumWidth }

        // Exactly as wide as the content, so dragging stops once none of it is
        // hidden — bounded by the screen, which is as far as a window goes.
        return min(naturalWidth, resizer.visibleScreenWidth ?? naturalWidth)
    }

    private var windowConstraints: WindowConstraints {
        WindowConstraints(
            heightIsFixed: !heightOverflows,
            widthIsFixed: !widthOverflows,
            minWidth: effectiveMinWidth,
            maxWidth: dragMaximumWidth
        )
    }

    private var toolbarController: DetailToolbarController {
        injectedToolbarController ?? ownToolbarController
    }

    private var toolbarTabs: [DetailToolbarController.Tab] {
        Array(Tab.allCases).map {
            .init(title: tabTitle($0), icon: tabIcon($0))
        }
    }

    private var sizedContent: some View {
        DetailLayout(
            minWidth: effectiveMinWidth,
            maxWidth: maximumWidth,
            onIdealSize: fitTo
        ) {
            tabContent(displayedTab)
                .frame(maxWidth: tabContentWidth(displayedTab) ?? .infinity)
                .frame(maxWidth: .infinity)
        }
    }

    private func fitTo(idealSize: CGSize) {
        // Zero from a tab with a bound is unbounded content, not empty.
        let unbounded = idealSize.height <= 0 && tabMaxHeight(displayedTab) != nil
        let ideal = unbounded ? heightCap : idealSize.height
        guard ideal > 0 else { return }

        let height = min(max(ideal, minimumHeight), heightCap)

        let width = min(max(idealSize.width, effectiveMinWidth), maximumWidth)

        // Only content the window cannot show all of is worth dragging for.
        // Unbounded content scrolls both ways, so it always has more to give.
        let overflowsHeight = unbounded || ideal > height + 0.5
        let overflowsWidth = idealSize.width > width + 0.5

        // `awaitMeasurement` waits on the first report after a swap, so it
        // gets through even when it matches the outgoing height.
        guard
            !hasMeasured
                || abs(measuredHeight - height) > 0.5
                || abs(measuredWidth - width) > 0.5
                || abs(naturalWidth - idealSize.width) > 0.5
                || overflowsHeight != heightOverflows
                || overflowsWidth != widthOverflows
        else { return }

        // Runs from layout, so the writes are deferred.
        Task { @MainActor in
            measuredHeight = height
            measuredWidth = width
            naturalWidth = idealSize.width
            heightOverflows = overflowsHeight
            widthOverflows = overflowsWidth
            hasMeasured = true
        }
    }

    var body: some View {
        // The window sizes itself from this spacer, never the content: an
        // overlay does not report its height, and the width must be the
        // placeholder's or SwiftUI widens from the left edge, off centre.
        Color.clear
            // Both axes flexible: `maximumWidth` is how wide the window
            // opens, which the fit applies — capping the layout with it too
            // left the content 900 wide inside a window dragged wider, so the
            // extra was empty and the content stayed hidden.
            .frame(minWidth: defaultMinWidth, maxWidth: .infinity)
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
            .onChange(of: windowConstraints, initial: true) { _, constraints in
                resizer.setConstraints(constraints)
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
                    await resizer.fit(
                        size: CGSize(width: measuredWidth, height: height),
                        duration: resizeDuration
                    )
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

        // Sizing before the toolbar lands measures the title bar alone, and
        // the toolbar then drags it straight — two moves for one appearance.
        if !hasAwaitedToolbar {
            hasAwaitedToolbar = true
            await toolbarController.whenSettled(timeout: toolbarTimeout)
        }

        while pendingTab != nil || needsRefit {
            guard pendingTab != nil else {
                needsRefit = false
                await resizer.fit(
                    size: CGSize(
                        width: measuredWidth,
                        height: measuredHeight
                    ),
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
            await resizer.fit(
                size: CGSize(width: measuredWidth, height: measuredHeight),
                duration: resizeDuration
            )
            guard pendingTab == nil else { continue }

            await fade(to: 1)
        }

        await fade(to: 1)
    }

    /// For a tab that fetches its own data, the whole of the load.
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

    private struct DetailLayout: Layout {
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let onIdealSize: @MainActor @Sendable (CGSize) -> Void

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            guard let subview = subviews.first else { return .zero }

            // Nothing proposed, so this is the content's own width — except
            // for content that scrolls, which answers with its viewport and
            // has to declare the width it holds instead.
            let declared = subview.contentIdealSize
            let natural = declared.width > 0 ? declared.width :
            subview.sizeThatFits(.unspecified).width
            let width = min(max(natural, minWidth), maxWidth)

            // At that width, not the current one: the outgoing width reports
            // a height for a wrap about to change.
            // Content that scrolls reports zero unless it declared a height,
            // and zero is what marks it as unbounded further up.
            let height = subview.isContentUnbounded ? declared.height :
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height

            // A nil width is SwiftUI probing extremes; an unready tab
            // measures whatever it draws while empty.
            // Reported unclamped; the view applies the bounds and can see
            // when the content did not fit inside them.
            if proposal.width != nil, subview.isContentReady {
                MainActor.assumeIsolated {
                    onIdealSize(CGSize(width: natural, height: height))
                }
            }

            return proposal.replacingUnspecifiedDimensions(
                by: CGSize(width: width, height: height)
            )
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
}
