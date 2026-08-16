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
    @Binding var force: Bool

    let tarContentTypes: [UTType]
    let defaultDirectory: URL?
    let onSelection: () -> Void

    var body: some View {
        FormStack {
            FormRow(
                title: "Tar Archive",
                description: "Select a tar archive containing the image"
            ) {
                FileSelection(
                    placeholder: "No tar archive selected",
                    fileURL: $tarFile,
                    allowedContentTypes: tarContentTypes,
                    defaultDirectory: defaultDirectory,
                    onSelection: onSelection
                )
            }

            Toggle(isOn: $force) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force load")
                    Text(
                        "Load images even when the archive contains invalid or rejected paths."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
    }
}
