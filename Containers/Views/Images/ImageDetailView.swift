//
//  ImageDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ImageDetailWindow: View {
    @Environment(ImageManager.self) private var imageManager
    let imageReference: String

    @SwiftUI.State private var image: ImageViewModel?
    @SwiftUI.State private var isLoading: Bool = true

    var body: some View {
        Group {
            if let image {
                ImageDetailView(image: image)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 550, height: 320)
            } else {
                ContentUnavailableView(
                    "Image Not Found",
                    systemImage: "shippingbox",
                    description: Text(
                        "The image '\(imageReference)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .navigationTitle(
            image.map { Text("\($0.name):\($0.tag)") }
                ?? Text("Image")
        )
        .task(id: imageReference) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await imageManager.list(platform: .current)
            if let match = items.first(where: {
                $0.description.reference == imageReference
            }) {
                image = ImageViewModel(match)
            } else {
                image = nil
            }
        } catch {
            image = nil
        }
    }
}

struct ImageDetailView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    let image: ImageViewModel

    @SwiftUI.State private var selectedCategory: DetailCategory = .overview
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showCreateContainer: Bool = false
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case history
        case inspect
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            showTabs: true,
            actions: actions,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { category in
                switch category {
                case .overview: "info.circle"
                case .history: "clock.arrow.circlepath"
                case .inspect: "curlybraces"
                }
            },
            tabWidth: { category in
                category == .inspect ? 750 : 650
            },
            tabMaxHeight: { category in
                switch category {
                case .overview: nil
                case .history: 430
                case .inspect: 500
                }
            },
            tabContent: { category in
                switch category {
                case .overview:
                    ImageOverview(image: image)

                case .inspect:
                    ImageInspect(image: image)

                case .history:
                    ImageHistory(
                        imageReference: image.imageDescription.reference,
                        platform: Platform.current
                    )
                }
            }
        )
        .sheet(isPresented: $showCreateContainer) {
            CreateContainerView(
                imageReference: image.imageDescription.reference,
                mode: .run
            )
        }
        .confirmationDialog(
            "Delete Image?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteImage()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Delete \(image.name):\(image.tag)? This cannot be undone."
            )
        }
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") { showError = false }
            },
            message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        )
    }

    private var actions: [DetailAction] {
        [
            DetailAction(
                id: "run",
                title: "Run",
                icon: "play.fill",
                help: "Run container"
            ) {
                showCreateContainer = true
            },
            DetailAction(
                id: "save",
                title: "Save",
                icon: "folder.fill",
                help: "Save image"
            ) {
                SaveImagePanel.present(
                    image: image.imageDescription,
                    imageManager: imageManager,
                    onError: { err in
                        self.error = err
                        self.showError = true
                    }
                )
            },
            DetailAction(
                id: "delete",
                title: "Delete",
                icon: "trash",
                help: "Delete image",
                isDestructive: true
            ) {
                showDeleteConfirmation = true
            },
        ]
    }

    private func deleteImage() {
        Task {
            do {
                try await imageManager.delete(images: [image.imageDescription])
                dismissWindow(
                    id: ContainersApp.imageDetailWindowID,
                    value: image.imageDescription.reference
                )
            } catch {
                self.error = error
                self.showError = true
            }
        }
    }
}
