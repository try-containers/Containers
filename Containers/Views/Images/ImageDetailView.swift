//
//  ImageDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import SwiftUI
import Containerization
import ContainerSystem
import ContainerizationOCI

struct ImageDetailView: View {
    let image: ImageViewModel
    let createContainer: () -> Void
    
    @Environment(\.close) private var close
    
    @Binding var showSaveImage: Bool
    @Binding var showDeleteConfirmation: Bool
    
    @SwiftUI.State private var selectedCategory: DetailCategory = .overview
    
    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case history
        case inspect
    }
    
    init(
        image: ImageViewModel,
        selectedTab: DetailCategory = .overview,
        createContainer: @escaping ()-> Void,
        showSaveImage: Binding<Bool>,
        showDeleteConfirmation: Binding<Bool>
    ) {
        self.image = image
        self.createContainer = createContainer
        self._selectedCategory = State(initialValue: selectedTab)
        self._showDeleteConfirmation = showDeleteConfirmation
        self._showSaveImage = showSaveImage
    }
    
    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            showTabs: true,
            usesFixedMaximumHeight: false,
            onClose: close,
            header: {
                Text(image.name)
                    .font(.title2)
                    .fontWeight(.semibold)
            },
            actionButtons: {
                actionButtons
            },
            tabTitle: { category in
                category.rawValue.localizedCapitalized
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
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        ActionButton(
            label: "Container",
            icon: "cube.fill",
            help: "Create container"
        ) {
            createContainer()
        }
        
        ActionButton(
            label: "Save",
            icon: "folder.fill",
            help: "Save image"
        ) {
            showSaveImage = true
        }
        
        ActionButton(
            label: "Delete",
            icon: "trash",
            help: "Delete image",
            role: .destructive
        ) {
            showDeleteConfirmation = true
        }
        .foregroundStyle(Color.red)
    }
}
