//
//  VolumeDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import ContainerSystem
import SwiftUI

struct VolumeDetailView: View {
    let volume: VolumeViewModel

    @Environment(\.dismiss) private var dismiss
    @SwiftUI.State private var selectedCategory: DetailCategory = .overview

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case inspect
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            onClose: { dismiss() },
            header: {
                Text(volume.name)
                    .font(.title2)
                    .fontWeight(.semibold)
            },
            actionButtons: {
                EmptyView()
            },
            tabTitle: { category in
                category.rawValue.localizedCapitalized
            },
            fixedHeightTab: { category in
                category != .overview
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
