//
//  LoadTarImageView.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct LoadTarImageView: View {
    @Binding var tarFile: URL?

    let tarContentTypes: [UTType]
    let defaultDirectory: URL?
    let onSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            FileSelection(
                title: "Tar Archive",
                description: "Select a tar archive containing the image",
                placeholder: "No tar archive selected",
                fileURL: $tarFile,
                allowedContentTypes: tarContentTypes,
                defaultDirectory: defaultDirectory,
                onSelection: onSelection
            )
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
    }
}
