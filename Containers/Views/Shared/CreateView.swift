//
//  CreateView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/05.
//

import SwiftUI

struct CreateView<Content: View, Actions: View, Progress: View, TabBar: View>: View {
    let title: String
    let errorMessage: Binding<String?>
    let isProcessing: Bool
    let progressTitle: String?
    let width: CGFloat
    let height: CGFloat
    let showsHeader: Bool
    let contentAlignment: Alignment
    let scrollsContent: Bool
    let contentID: AnyHashable?
    let contentTransition: AnyTransition
    let contentPadding: CGFloat
    let onCancel: () -> Void
    let tabBar: TabBar
    let content: Content
    let actions: Actions
    let progress: Progress

    init(
        title: String,
        errorMessage: Binding<String?> = .constant(nil),
        isProcessing: Bool = false,
        progressTitle: String? = nil,
        width: CGFloat,
        height: CGFloat,
        showsHeader: Bool = true,
        contentAlignment: Alignment = .topLeading,
        scrollsContent: Bool = false,
        contentPadding: CGFloat = 20,
        contentID: AnyHashable? = nil,
        contentTransition: AnyTransition = .identity,
        onCancel: @escaping () -> Void,
        @ViewBuilder tabBar: () -> TabBar = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder progress: () -> Progress = { EmptyView() }
    ) {
        self.title = title
        self.errorMessage = errorMessage
        self.isProcessing = isProcessing
        self.progressTitle = progressTitle
        self.width = width
        self.height = height
        self.showsHeader = showsHeader
        self.contentAlignment = contentAlignment
        self.scrollsContent = scrollsContent
        self.contentPadding = contentPadding
        self.contentID = contentID
        self.contentTransition = contentTransition
        self.onCancel = onCancel
        self.tabBar = tabBar()
        self.content = content()
        self.actions = actions()
        self.progress = progress()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            if TabBar.self != EmptyView.self {
                Divider()

                tabBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            contentArea

            Divider()

            footer
        }
        .frame(width: width, height: height)
        .interactiveDismissDisabled(isProcessing)
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage.wrappedValue = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    errorMessage.wrappedValue = nil
                }
            },
            message: {
                Text(errorMessage.wrappedValue ?? "")
            }
        )
    }

    private var contentArea: some View {
        ZStack(alignment: contentAlignment) {
            contentContainer
                .id(contentID)
                .transition(contentTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(isProcessing ? 0 : 1)
        .overlay {
            if isProcessing {
                progressStatus
            }
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        if scrollsContent {
            ScrollView {
                content
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .padding(contentPadding)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: contentAlignment
                )
        }
    }

    private var progressStatus: some View {
        VStack(spacing: 12) {
            ProgressView()

            VStack(spacing: 4) {
                if let progressTitle {
                    Text(progressTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                progress
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            actions
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
struct CreateViewTabBar<Tab: Hashable & CaseIterable & RawRepresentable>: View
where Tab.AllCases: RandomAccessCollection, Tab.RawValue == String {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                tabButton(for: tab)
            }
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        TabButton(tab: tab, selection: $selection)
    }
}

private struct TabButton<Tab: Hashable & RawRepresentable>: View
where Tab.RawValue == String {
    let tab: Tab
    @Binding var selection: Tab
    @State private var isHovered = false

    var body: some View {
        Button {
            selection = tab
        } label: {
            Text(tab.rawValue)
                .foregroundStyle(tab == selection ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if tab == selection {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color(nsColor: .quaternaryLabelColor)
        } else {
            return .clear
        }
    }
}

