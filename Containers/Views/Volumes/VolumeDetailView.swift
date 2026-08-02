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

    var body: some View {
        Group {
            if let volume {
                VolumeDetailView(volume: volume)
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.width,
                        height: DetailPlaceholder.height
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
        .navigationTitle(
            volume.map { Text($0.name) }
                ?? Text("Volume")
        )
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

    @SwiftUI.State private var selectedCategory: DetailCategory = .overview

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case inspect
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            tabIcon: { category in
                switch category {
                case .overview: "info.circle"
                case .inspect: "curlybraces"
                }
            },
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
