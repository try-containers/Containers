//
//  ImageSelectionView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerizationOCI
import ContainerResource

struct ImageSelectionView: View {
    var images: [ImageDescription]
    var onImageSelect: (String) -> Void
    
    @SwiftUI.State private var searchText: String = ""
    
    @Environment(\.dismiss) private var dismiss

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredImages: [ImageDescription] {
        if trimmedText.isEmpty {
            return images
        }
        let filtered = self.images.filter({
            $0.reference.contains(trimmedText)
        })
        
        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            List {
                ForEach(filteredImages, id: \.digest) { image in
                    Button(action: {
                        self.onImageSelect(image.reference)
                        self.dismiss()
                    }, label: {
                        Text(image.reference)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    })

                }
            }
            .searchable(text: $searchText)
            .buttonStyle(.plain)
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(RoundedRectangle(cornerRadius: 4).fill(.clear).stroke(.secondary, style: .init(lineWidth: 1)))
            
            Button(action: {
                self.dismiss()
            }, label: {
                Text("Cancel")
                    .padding(.horizontal, 2)
            })
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)
        
            
        }
        .multilineTextAlignment(.leading)
        .padding(.all, 24)
        .frame(width: 440, height: 400)
        .interactiveDismissDisabled(false)

    }
}
