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
    
    @Environment(\.dismiss) private var dismiss
    
    @SwiftUI.State private var selectedCategory: DetailCategory = .history
    
    enum DetailCategory: String, CaseIterable, Identifiable {
        case inspect = "Inspect"
        case history = "History"
        
        var id: String {
            return self.rawValue
        }
        
        static let allCases: [DetailCategory] = [.inspect, .history]
    }
    
    init(image: ImageViewModel, selectedTab: DetailCategory = .inspect) {
        self.image = image
        self._selectedCategory = State(initialValue: selectedTab)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            Group {
                switch self.selectedCategory {
                case .inspect:
                    ImageInspectView(image: image)
                case .history:
                    ImageHistoryView(
                        imageReference: image.imageDescription.reference,
                        platform: Platform.current
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 700, height: 600)
    }
}
