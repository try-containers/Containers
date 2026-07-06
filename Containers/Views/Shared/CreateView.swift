//
//  CreateView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/05.
//

import SwiftUI

struct CreateView<Content: View, Actions: View, Progress: View>: View {
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
    let onCancel: () -> Void
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
        contentID: AnyHashable? = nil,
        contentTransition: AnyTransition = .identity,
        onCancel: @escaping () -> Void,
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
        self.contentID = contentID
        self.contentTransition = contentTransition
        self.onCancel = onCancel
        self.content = content()
        self.actions = actions()
        self.progress = progress()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
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
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .padding(20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: contentAlignment
                )
        }
    }

    private var header: some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
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
        HStack(spacing: 16) {
            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            actions
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
