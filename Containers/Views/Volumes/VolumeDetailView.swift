//
//  VolumeDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import ContainerSystem
import SwiftUI

struct VolumeDetailWindow: View {
    @Environment(VolumeManager.self) private var volumeManager

    let id: String

    @SwiftUI.State private var volume: VolumeViewModel?
    @SwiftUI.State private var isLoading: Bool = true
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let volume {
                VolumeDetailView(
                    volume: volume,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.volume.width,
                        height: DetailPlaceholder.volume.height
                    )
            } else {
                ContentUnavailableView(
                    "Volume Not Found",
                    systemImage: "externaldrive",
                    description: Text(
                        "The volume '\(id)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: VolumeDetailView.toolbarTabs,
                actions: []
            )
        )
        // Empty until the volume arrives, rather than a placeholder the user
        // watches get replaced.
        .navigationTitle(volume.map { Text($0.name) } ?? Text(""))
        .task(id: id) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await volumeManager.listWithUsage()
            if let match = items.first(where: { $0.volume.id == id }) {
                self.volume = VolumeViewModel(match)
            } else {
                self.volume = nil
            }
        } catch {
            self.volume = nil
        }
    }
}

struct VolumeDetailView: View {
    let volume: VolumeViewModel
    let toolbarController: DetailToolbarController

    @SwiftUI.State private var selectedCategory: DetailCategory = .overview

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
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
        case .inspect: "curlybraces"
        }
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
            tabMaxHeight: { category in
                switch category {
                case .overview: nil
                case .inspect: 500
                }
            },
            tabContentWidth: { category in
                switch category {
                case .overview: DetailPlaceholder.width
                case .inspect: nil
                }
            },
            toolbarController: toolbarController,
            tabContent: { category in
                switch category {
                case .overview:
                    VolumeOverview(volume: volume)
                case .inspect:
                    VolumeInspect(volume: volume)
                }
            }
        )
    }
}
