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

struct DetailView<
    Tab: Hashable & CaseIterable,
    Content: View
>: View where Tab.AllCases: RandomAccessCollection {
    private var minimumWidth: CGFloat { 550 }
    private var maximumWidth: CGFloat { 900 }
    private var minimumHeight: CGFloat { 300 }
    private var maximumHeight: CGFloat { 480 }

    let showTabs: Bool
    let actions: [DetailAction]

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabIcon: (Tab) -> String
    let tabWidth: (Tab) -> CGFloat?
    let tabContent: (Tab) -> Content

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        actions: [DetailAction] = [],
        tabTitle: @escaping (Tab) -> String,
        tabIcon: @escaping (Tab) -> String,
        tabWidth: @escaping (Tab) -> CGFloat? = { _ in nil },
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self._selectedTab = selectedTab
        self.showTabs = showTabs
        self.actions = actions
        self.tabTitle = tabTitle
        self.tabIcon = tabIcon
        self.tabWidth = tabWidth
        self.tabContent = tabContent
    }

    private var effectiveMinimumWidth: CGFloat {
        tabWidth(selectedTab) ?? minimumWidth
    }

    var body: some View {
        tabContent(selectedTab)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(
                minWidth: effectiveMinimumWidth,
                maxWidth: maximumWidth,
                minHeight: minimumHeight,
                maxHeight: maximumHeight
            )
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
            .background(DetailWindowConfigurator())
    }
}

private struct DetailWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.tabbingMode = .disallowed
    }
}
