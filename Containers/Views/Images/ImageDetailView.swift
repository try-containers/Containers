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
    
    @Environment(\.dismiss) private var dismiss
    
    @Binding var showSaveImage: Bool
    @Binding var showDeleteConfirmation: Bool
    
    @SwiftUI.State private var selectedCategory: DetailCategory = .inspect
    
    enum DetailCategory: String, CaseIterable, Hashable {
        case inspect
        case history
    }
    
    init(
        image: ImageViewModel,
        selectedTab: DetailCategory = .inspect,
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
            showTabs: false,
            onClose: {
                dismiss()
            },
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
                case .inspect:
                    ImageInspectView(image: image)
                    
                case .history:
                    ImageHistoryView(
                        imageReference: image.imageDescription.reference,
                        platform: Platform.current
                    )
                }
            }
        )
        .frame(width: 700, height: 600)
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
    }
}
