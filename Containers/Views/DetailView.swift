//
//  DetailView.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import SwiftUI

struct DetailView<
    Tab: Hashable & CaseIterable,
    Header: View,
    ActionButtons: View,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private static var width: CGFloat { 550 }
    private static var maximumContentHeight: CGFloat { 480 }
    private static var tabTransitionAnimation: Animation {
        .easeInOut(duration: 0.22)
    }

    let onClose: () -> Void
    let showTabs: Bool
    let usesFixedMaximumHeight: Bool
    let header: Header
    let actionButtons: ActionButtons

    @Binding var selectedTab: Tab

    @State private var displayedTab: Tab
    @State private var contentHeight: CGFloat = 0
    @State private var isTabContentVisible = false
    @State private var tabSwitchGeneration = 0
    @State private var pendingResizeCompletion: (@MainActor () -> Void)?
    /// True until the first real height measurement comes in and the content
    /// has faded in for the first time. Lets `onPreferenceChange` tell apart
    /// "this is the very first measurement, on initial appearance" from
    /// "this is a remeasure following a tab switch" — the former needs to
    /// trigger its own fade-in once the height settles; the latter is already
    /// handled by `switchDisplayedTab`'s own fade logic.
    @State private var isInitialReveal = true

    let tabTitle: (Tab) -> String
    let fixedHeightTab: (Tab) -> Bool
    let tabContent: (Tab) -> Content

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        usesFixedMaximumHeight: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder actionButtons: () -> ActionButtons,
        tabTitle: @escaping (Tab) -> String,
        fixedHeightTab: @escaping (Tab) -> Bool = { _ in false },
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self._selectedTab = selectedTab
        self._displayedTab = State(initialValue: selectedTab.wrappedValue)
        self.onClose = onClose
        self.showTabs = showTabs
        self.usesFixedMaximumHeight = usesFixedMaximumHeight
        self.header = header()
        self.actionButtons = actionButtons()
        self.tabTitle = tabTitle
        self.fixedHeightTab = fixedHeightTab
        self.tabContent = tabContent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if showTabs {
                tabBar
                Divider()
            }

            contentArea

            Divider()

            footer
        }
        .frame(width: Self.width)
        .background(alignment: .top) {
            tabContent(displayedTab)
                .frame(maxWidth: 600)
                .frame(width: Self.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: DetailViewHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                    }
                }
        }
        .onPreferenceChange(DetailViewHeightPreferenceKey.self) { height in
            let newHeight =
                if fixedHeightTab(displayedTab) {
                    Self.maximumContentHeight
                } else if usesFixedMaximumHeight {
                    min(height, Self.maximumContentHeight)
                } else {
                    height
                }

            let completion = pendingResizeCompletion
            pendingResizeCompletion = nil

            // On the very first measurement (initial appearance), there's no
            // tab-switch fade in flight — content has been invisible since
            // `isTabContentVisible` starts `false`. Once we know the real
            // height, lock it in and fade the content in for the first time,
            // exactly like a tab switch's own reveal. This keeps first load
            // and tab switches visually identical instead of first load
            // rendering at a natural size before snapping to the locked height.
            if isInitialReveal {
                isInitialReveal = false
                contentHeight = newHeight
                isTabContentVisible = true
                completion?()
                return
            }

            if newHeight == contentHeight {
                completion?()
            } else {
                withAnimation(Self.tabTransitionAnimation) {
                    contentHeight = newHeight
                } completion: {
                    completion?()
                }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            switchDisplayedTab(to: newValue)
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                header
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                actionButtons
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { switchDisplayedTab(to: $0) }
        )
    }

    private var tabBar: some View {
        Picker(
            selection: tabSelection,
            content: {
                ForEach(Array(Tab.allCases), id: \.self) { tab in
                    Text(tabTitle(tab))
                        .tag(tab)
                }
            },
            label: {}
        )
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var contentArea: some View {
        ZStack(alignment: .top) {
            tabContent(displayedTab)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, alignment: .top)
                .opacity(isTabContentVisible ? 1 : 0)
        }
        .frame(
            height: contentHeight == 0 ? nil : contentHeight,
            alignment: .top
        )
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button {
                onClose()
            } label: {
                Text("Close")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab switching

    private func switchDisplayedTab(to tab: Tab) {
        guard tab != displayedTab || tab != selectedTab else { return }

        tabSwitchGeneration += 1
        let generation = tabSwitchGeneration
        selectedTab = tab

        withAnimation(Self.tabTransitionAnimation) {
            isTabContentVisible = false
        } completion: {
            guard generation == tabSwitchGeneration else { return }

            pendingResizeCompletion = {
                guard generation == tabSwitchGeneration else { return }
                fadeIn(generation: generation)
            }
            displayedTab = tab
        }
    }

    private func fadeIn(generation: Int) {
        guard generation == tabSwitchGeneration else { return }
        withAnimation(Self.tabTransitionAnimation) {
            isTabContentVisible = true
        }
    }
}

// MARK: - Preference Key

private struct DetailViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
