//
//  CreateView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/05.
//

import SwiftUI

struct CreateView<Content: View, Actions: View, Progress: View, TabBar: View>:
    View
{
    let title: String
    let error: Binding<ErrorAlert?>
    let isProcessing: Bool
    let progressTitle: String?
    let width: CGFloat
    let height: CGFloat
    let showsHeader: Bool
    let contentAlignment: Alignment
    let scrollsContent: Bool
    let showsFooterDivider: Bool
    let contentID: AnyHashable?
    let contentTransition: AnyTransition
    let contentPadding: CGFloat
    let contentTitle: String?
    let contentTitleRule: Bool
    let tabBar: TabBar
    let content: Content
    let actions: Actions
    let progress: Progress

    init(
        title: String,
        error: Binding<ErrorAlert?> = .constant(nil),
        isProcessing: Bool = false,
        progressTitle: String? = nil,
        width: CGFloat,
        height: CGFloat,
        showsHeader: Bool = true,
        contentAlignment: Alignment = .topLeading,
        scrollsContent: Bool = false,
        showsFooterDivider: Bool = true,
        contentPadding: CGFloat = 20,
        contentID: AnyHashable? = nil,
        contentTransition: AnyTransition = .identity,
        contentTitle: String? = nil,
        contentTitleRule: Bool = false,
        @ViewBuilder tabBar: () -> TabBar = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder progress: () -> Progress = { EmptyView() }
    ) {
        self.title = title
        self.error = error
        self.isProcessing = isProcessing
        self.progressTitle = progressTitle
        self.width = width
        self.height = height
        self.showsHeader = showsHeader
        self.contentAlignment = contentAlignment
        self.scrollsContent = scrollsContent
        self.showsFooterDivider = showsFooterDivider
        self.contentPadding = contentPadding
        self.contentID = contentID
        self.contentTransition = contentTransition
        self.contentTitle = contentTitle
        self.contentTitleRule = contentTitleRule
        self.tabBar = tabBar()
        self.content = content()
        self.actions = actions()
        self.progress = progress()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Working, the sheet is only its progress and the buttons that
            // answer it: the title and the steps it names are gone.
            if showsHeader && !isProcessing {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            if TabBar.self != EmptyView.self && !isProcessing {
                Divider()

                tabBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            contentArea

            if showsFooterDivider {
                Divider()
            }

            footer
        }
        .frame(width: width, height: height)
        // Centred on the sheet rather than on what is left above the buttons,
        // and never in the way of the one button that answers it.
        .overlay {
            if isProcessing {
                progressStatus
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .interactiveDismissDisabled(isProcessing)
        .errorAlert(error)
    }

    private var contentArea: some View {
        // The header sits outside the transition: it belongs to the sheet
        // rather than to the step, so it does not slide or fade with one.
        VStack(alignment: .leading, spacing: 0) {
            // The step change animates the content across; the title going
            // with it is the sheet's furniture moving, so it changes instantly.
            Group {
                if let contentTitle {
                    Text(contentTitle)
                        .padding(.horizontal, contentPadding)
                        .padding(.top, contentPadding)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Ruled off directly under the title, so the rule belongs
                    // to it rather than to whatever the step puts below.
                    if contentTitleRule {
                        Divider()
                    }
                }
            }
            .transaction { $0.animation = nil }

            ZStack(alignment: contentAlignment) {
                contentContainer
                    .id(contentID)
                    .transition(contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(isProcessing ? 0 : 1)
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
                        .font(.body)
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
            actions
        }
        .controlSize(.regular)
        .padding(16)
        // The step change animates the content across; the buttons swapping
        // with it reads as a glitch, so they change instantly.
        .transaction { $0.animation = nil }
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
                .foregroundStyle(
                    tab == selection ? Color.accentColor : .primary
                )
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
