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
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let image {
                ImageDetailView(
                    image: image,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.image.width,
                        height: DetailPlaceholder.image.height
                    )
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
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: ImageDetailView.toolbarTabs,
                actions: ImageDetailView.placeholderActions
            )
        )
        .navigationTitle(
            image.map { Text("\($0.name):\($0.tag)") } ?? Text("")
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
    let toolbarController: DetailToolbarController

    @SwiftUI.State private var selectedCategory: DetailCategory = .overview
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showCreateContainer: Bool = false
    @SwiftUI.State private var errorAlert: ErrorAlert?

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case history
        case inspect
    }

    static var toolbarTabs: [DetailToolbarController.Tab] {
        DetailCategory.allCases.map {
            .init(title: $0.rawValue.localizedCapitalized, icon: tabIcon($0))
        }
    }

    static func tabIcon(_ tab: DetailCategory) -> String {
        switch tab {
        case .overview: "info.circle"
        case .history: "clock.arrow.circlepath"
        case .inspect: "curlybraces"
        }
    }

    /// The same shape with nothing wired up, so the window can build its
    /// toolbar before it has an image to build one from.
    static var placeholderActions: [DetailAction] {
        [
            DetailAction(id: "run", title: "Run", icon: "play.fill", isEnabled: false) {},
            DetailAction(id: "save", title: "Save", icon: "folder.fill", isEnabled: false) {},
            DetailAction(
                id: "delete",
                title: "Delete",
                icon: "trash",
                isEnabled: false,
                isDestructive: true
            ) {},
        ]
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            showTabs: true,
            actions: actions,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
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
            tabContentWidth: { category in
                switch category {
                case .overview: 650
                case .history, .inspect: nil
                }
            },
            toolbarController: toolbarController,
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
        .errorAlert($errorAlert)
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
                        self.errorAlert = ErrorAlert(
                            "The image couldn’t be saved.",
                            error: err
                        )
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
                self.errorAlert = ErrorAlert(
                    "The image couldn’t be deleted.",
                    error: error
                )
            }
        }
    }
}
