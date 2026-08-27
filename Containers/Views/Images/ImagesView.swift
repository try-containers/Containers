//
//  ImagesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI
import TipKit

struct ImagesView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String

    var refreshTrigger: Int
    var onRefresh: (() async -> Void)? = nil

    private let runContainerTip = RunContainerTip()

    @SwiftUI.State private var images: [ImageViewModel] = []
    @SwiftUI.State private var lastUpdated: Date? = nil
    @SwiftUI.State private var createContainerForImage: ImageViewModel? = nil
    @SwiftUI.State private var imageToDelete: ImageViewModel?
    @SwiftUI.State private var errorAlert: ErrorAlert?
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showInUseContainerForImage: ImageViewModel?

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredImages: [ImageViewModel] {
        if trimmedText.isEmpty {
            return images
        }

        let filtered = self.images.filter({
            $0.name.contains(trimmedText) || $0.tag.contains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        TableView(
            rows: filteredImages,
            refreshTrigger: refreshTrigger,
            lastUpdated: lastUpdated,
            isFiltering: !trimmedText.isEmpty,
            onClear: {
                images = []
                lastUpdated = nil
            },
            onRefresh: listImages
        ) {
            TableColumn("Name") { image in
                Button(action: {
                    openWindow(
                        id: ContainersApp.imageDetailWindowID,
                        value: image.imageDescription.reference
                    )
                }) {
                    Text(image.name)
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .pointerStyle(.link)
                .underline()
            }
            .width(min: 150, ideal: 180)

            TableColumn("Tag") { image in
                Text(image.tag)
                    .lineLimit(1)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Digest") { image in
                Text(image.formattedDigest)
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .width(min: 100, ideal: 120, max: 140)

            TableColumn("State") { image in
                Group {
                    if image.inUse {
                        Button(
                            action: {
                                showInUseContainerForImage = image
                            },
                            label: {
                                Text("In use")
                                    .lineLimit(1)
                                    .underline()
                            }
                        )
                        .buttonStyle(.link)
                        .pointerStyle(.link)
                        .popover(
                            isPresented: Binding(
                                get: {
                                    showInUseContainerForImage?.id == image.id
                                },
                                set: {
                                    if !$0 { showInUseContainerForImage = nil }
                                }
                            ),
                            arrowEdge: .bottom
                        ) {
                            ImageContainersView(image: image)
                        }
                    } else {
                        Text("Unused")
                    }
                }
                .lineLimit(1)
            }
            .width(min: 60, ideal: 70)

            TableColumn("Actions") { image in
                HStack(spacing: 12) {
                    Button(
                        action: {
                            runContainerTip.invalidate(reason: .actionPerformed)
                            self.createContainerForImage = image
                        },
                        label: {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.blue)
                        }
                    )
                    .buttonStyle(.plain)
                    .help("Run container from image")
                    .popoverTip(
                        runContainerTip,
                        when: image.id == filteredImages.first?.id
                    )

                    Button(
                        action: {
                            imageToDelete = image
                            showDeleteConfirmation = true
                        },
                        label: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(
                                    image.inUse ? .secondary : Color.red
                                )
                        }
                    )
                    .disabled(image.inUse)
                    .buttonStyle(.plain)
                    .help("Delete image")
                }
                .padding(.horizontal, 8)
            }
            .width(128)
        }
        .sheet(
            item: $createContainerForImage,
            onDismiss: {
                Task {
                    await self.listImages()
                }
            },
            content: { image in
                CreateContainerView(
                    imageReference: image.imageDescription.reference,
                    mode: .run
                )
            }
        )
        .errorAlert($errorAlert)
        .confirmationDialog(
            "Delete Image?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let image = imageToDelete else {
                    return
                }

                Task {
                    do {
                        try await imageManager.delete(images: [
                            image.imageDescription
                        ])

                        await self.listImages()
                    } catch (let err) {
                        self.errorAlert = ErrorAlert(
                            "The image couldn’t be deleted.",
                            error: err
                        )
                    }
                }

                imageToDelete = nil
            }

            Button("Cancel", role: .cancel) {
                imageToDelete = nil
            }
        } message: {
            if let image = imageToDelete {
                Text(
                    "Delete \(image.name):\(image.tag)? This cannot be undone."
                )
            }
        }
    }

    func listImages() async {
        do {
            let images = try await imageManager.list(platform: .current)

            self.images =
                images
                .map(ImageViewModel.init)
                .sorted { ($0.name, $0.tag) < ($1.name, $1.tag) }
            self.lastUpdated = Date()

        } catch (let err) {
            self.errorAlert = ErrorAlert(
                "The images couldn’t be loaded.",
                error: err
            )
        }
    }
}

#Preview {
    ImagesView(
        searchText: .constant(""),
        refreshTrigger: 0
    )
    .environment(ContainerManager())
}
