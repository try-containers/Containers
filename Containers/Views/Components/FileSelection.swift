//
//  FileSelection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileSelection: View {
    let title: String
    let description: String?
    let placeholder: String
    let fileURL: Binding<URL?>
    let allowedContentTypes: [UTType]
    let canChooseDirectories: Bool
    let defaultDirectory: URL?
    let onSelection: (() -> Void)?
    let isPresented: Binding<Bool>?

    init(
        title: String,
        description: String? = nil,
        placeholder: String,
        fileURL: Binding<URL?>,
        allowedContentTypes: [UTType] = [],
        canChooseDirectories: Bool = false,
        defaultDirectory: URL? = nil,
        onSelection: (() -> Void)? = nil,
        isPresented: Binding<Bool>? = nil
    ) {
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.fileURL = fileURL
        self.allowedContentTypes = allowedContentTypes
        self.canChooseDirectories = canChooseDirectories
        self.defaultDirectory = defaultDirectory
        self.onSelection = onSelection
        self.isPresented = isPresented
    }

    var body: some View {
        HStack(alignment: .top) {
            Text("\(title):")
                .frame(
                    width: EditableFormLayout.labelWidth,
                    alignment: .trailing
                )
                .padding(.top, EditableFormLayout.fieldLabelTopPadding)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(fileURL.wrappedValue?.path ?? placeholder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(
                            fileURL.wrappedValue == nil ? .secondary : .primary
                        )
                        .padding(.horizontal, 8)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 22,
                            alignment: .leading
                        )
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .stroke(
                                    Color(nsColor: .separatorColor),
                                    lineWidth: 1
                                )
                        }

                    Button("Choose...", action: selectFile)
                }

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(
                width: EditableFormLayout.controlWidth,
                alignment: .leading
            )
        }
        .onChange(of: isPresented?.wrappedValue ?? false) { _, isPresented in
            guard isPresented else { return }
            selectFile()
            self.isPresented?.wrappedValue = false
        }
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = !canChooseDirectories
        panel.canChooseDirectories = canChooseDirectories
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = fileURL.wrappedValue?.parent ?? defaultDirectory

        if !allowedContentTypes.isEmpty {
            panel.allowedContentTypes = allowedContentTypes
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        fileURL.wrappedValue = url
        onSelection?()
    }
}
