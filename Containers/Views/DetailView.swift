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
    let onClose: () -> Void
    let showTabs: Bool
    let header: Header
    let actionButtons: ActionButtons

    @Binding var selectedTab: Tab

    let tabTitle: (Tab) -> String
    let tabContent: (Tab) -> Content

    init(
        selectedTab: Binding<Tab>,
        showTabs: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder actionButtons: () -> ActionButtons,
        tabTitle: @escaping (Tab) -> String,
        @ViewBuilder tabContent: @escaping (Tab) -> Content
    ) {
        self._selectedTab = selectedTab
        self.onClose = onClose
        self.showTabs = showTabs
        self.header = header()
        self.actionButtons = actionButtons()
        self.tabTitle = tabTitle
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
        .frame(width: 550, height: 600)
    }

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

    private var tabBar: some View {
        Picker(
            selection: $selectedTab,
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
        tabContent(selectedTab)
            .frame(maxWidth: 600, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
