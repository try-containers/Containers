//
//  ImageSelectionView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ImageSelectionView: View {
    var images: [ImageDescription]
    var onImageSelect: (String) -> Void

    @SwiftUI.State private var searchText: String = ""

    @Environment(\.close) private var close

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredImages: [ImageDescription] {
        let sorted = images.sorted { $0.reference < $1.reference }

        if trimmedText.isEmpty {
            return sorted
        }

        return sorted.filter({
            $0.reference.contains(trimmedText)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            List {
                ForEach(filteredImages, id: \.digest) { image in
                    Button(
                        action: {
                            self.onImageSelect(image.reference)
                            close()
                        },
                        label: {
                            Text(image.reference)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    )

                }
            }
            .searchable(text: $searchText)
            .buttonStyle(.plain)
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(
                RoundedRectangle(cornerRadius: 4).fill(.clear).stroke(
                    .secondary,
                    style: .init(lineWidth: 1)
                )
            )

            Button(
                action: {
                    close()
                },
                label: {
                    Text("Cancel")
                        .padding(.horizontal, 2)
                }
            )
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)

        }
        .multilineTextAlignment(.leading)
        .padding(.all, 24)
        .frame(width: 440, height: 400)
        .interactiveDismissDisabled(false)

    }
}
