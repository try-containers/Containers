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

            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            header
                        }
                        .padding(.leading, 10)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        actionButtons
                    }
                }
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Tabs
            if showTabs {
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
                
                Divider()
            }
            
            // Content
            tabContent(selectedTab)
                .frame(maxHeight: .infinity)

            Divider()

            // Footer
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
}

