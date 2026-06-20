//
//  FileSelection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import UniformTypeIdentifiers

extension FileSelection {
    init(
        fileURL: Binding<URL>,
        errorMessage: Binding<String?>,
        allowedContentTypes: [UTType]
    ) {
        let fileBinding = Binding<URL?>(
            get: {
                URL(filePath: fileURL.wrappedValue.absoluteString)
            },
            set: { newURL in
                if let newURL {
                    fileURL.wrappedValue = newURL
                }
            }
        )
        self._fileURL = fileBinding
        self._errorMessage = errorMessage
        self.allowedContentTypes = allowedContentTypes
    }
}

struct FileSelection: View {
    // file scheme, ie: file://
    @Binding var fileURL: URL?
    @Binding var errorMessage: String?

    var allowedContentTypes: [UTType]

    @State private var showImporter: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(fileURL?.absoluteString ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.5))
                        .stroke(
                            .secondary.opacity(0.8),
                            style: .init(lineWidth: 1)
                        )
                )

            Button {
                if let fileURL {
                    self.openFile(fileURL)
                }
            } label: {
                Image(systemName: "arrow.right")
                    .contentShape(Rectangle())
                    .fontWeight(.semibold)
            }
            .buttonStyle(.link)
            .pointerStyle(.link)
            .disabled(fileURL == nil)

            Spacer()

            Button(
                action: {
                    self.showImporter = true
                },
                label: {
                    Image(systemName: "ellipsis")
                        .padding(.horizontal, 2)
                        .frame(maxHeight: .infinity)
                }
            )
            .buttonStyle(.bordered)
            .pointerStyle(.link)

        }
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: self.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    self.errorMessage = "File Url is not available."
                    return
                }
                self.fileURL =
                    url.isFileURL
                    ? url
                    : URL(
                        filePath: url.absoluteString
                    )
            case .failure(let error):
                self.errorMessage = "failed to import file: \(error)."
                return
            }
        }
        .fileDialogBrowserOptions([.includeHiddenFiles])
        .fileDialogDefaultDirectory(
            fileURL?.parent
                ?? (try? FileManager.default
                    .url(
                        for: .desktopDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: false
                    ))
        )
        .fileDialogConfirmationLabel(Text("Select"))
    }

    private func openFile(_ url: URL) {
        let result = NSWorkspace.shared.selectFile(
            url.absoluteString,
            inFileViewerRootedAtPath: url.parent.absoluteString
        )
        if !result {
            self.errorMessage = "Failed to open the File."
        }
    }
}
