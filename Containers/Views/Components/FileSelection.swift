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
    let suggestedSaveFilename: String?
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
        suggestedSaveFilename: String? = nil,
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
        self.suggestedSaveFilename = suggestedSaveFilename
        self.onSelection = onSelection
        self.isPresented = isPresented
    }

    private var path: Binding<String> {
        Binding {
            fileURL.wrappedValue?.path ?? ""
        } set: { path in
            let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
            fileURL.wrappedValue = path.isEmpty ? nil : URL(filePath: path)
            onSelection?()
        }
    }

    var body: some View {
        EditableField(
            title: title,
            description: description,
            placeholder: placeholder,
            value: path,
            actionLabel: {
                Label("Browse", systemImage: "folder").labelStyle(.iconOnly)
            },
            action: selectFile
        )
        .onChange(of: isPresented?.wrappedValue ?? false) { _, isPresented in
            guard isPresented else { return }
            selectFile()
            self.isPresented?.wrappedValue = false
        }
    }

    private func selectFile() {
        if let suggestedSaveFilename {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.showsHiddenFiles = true
            panel.directoryURL =
                fileURL.wrappedValue?.parent ?? defaultDirectory
            panel.nameFieldStringValue =
                fileURL.wrappedValue?.lastPathComponent
                ?? suggestedSaveFilename

            if !allowedContentTypes.isEmpty {
                panel.allowedContentTypes = allowedContentTypes
            }

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }

            fileURL.wrappedValue = url
            onSelection?()
            return
        }

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
