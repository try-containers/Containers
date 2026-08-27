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
    /// How the choice is presented.
    enum Style {
        /// A pop-up of places to choose among, and nothing else: the path is
        /// picked, never written.
        case popUp
        /// The path itself, editable, beside a button that opens the panel —
        /// what suits a field whose answer can be written or made, not only
        /// found.
        case field
    }

    /// How the pop-up writes a location out.
    enum Label {
        /// The name Finder gives it, localised and without the path.
        case name
        /// The whole path, so two locations sharing a name stay apart.
        case path
    }

    /// A place the pop-up can offer.
    struct Location: Hashable, CustomStringConvertible {
        let url: URL?

        var description: String {
            url?.path ?? ""
        }

        var icon: NSImage? {
            guard let url else { return nil }

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
    }

    let placeholder: String
    let fileURL: Binding<URL?>
    let allowedContentTypes: [UTType]
    let canChooseDirectories: Bool
    let canCreateDirectories: Bool
    let defaultDirectory: URL?
    let locations: [URL]
    let style: Style
    let label: Label
    let recents: RecentLocations.Kind?
    let suggestedSaveFilename: String?
    let onSelection: (() -> Void)?
    let isPresented: Binding<Bool>?

    @Environment(\.isEnabled) private var isEnabled
    @SwiftUI.State private var recentURLs: [URL] = []

    init(
        placeholder: String,
        fileURL: Binding<URL?>,
        allowedContentTypes: [UTType] = [],
        canChooseDirectories: Bool = false,
        canCreateDirectories: Bool = false,
        defaultDirectory: URL? = nil,
        locations: [URL] = [],
        style: Style = .popUp,
        label: Label = .name,
        recents: RecentLocations.Kind? = nil,
        suggestedSaveFilename: String? = nil,
        onSelection: (() -> Void)? = nil,
        isPresented: Binding<Bool>? = nil
    ) {
        self.placeholder = placeholder
        self.fileURL = fileURL
        self.allowedContentTypes = allowedContentTypes
        self.canChooseDirectories = canChooseDirectories
        self.canCreateDirectories = canCreateDirectories
        self.defaultDirectory = defaultDirectory
        self.locations = locations
        self.style = style
        self.label = label
        self.recents = recents
        self.suggestedSaveFilename = suggestedSaveFilename
        self.onSelection = onSelection
        self.isPresented = isPresented
    }

    /// Files a picker can offer in place of the standard folders, gathered
    /// from `directories` without descending into them.
    static func files(
        in directories: [URL?],
        matching matches: (URL) -> Bool
    ) -> [URL] {
        var seen = Set<String>()

        return
            directories
            .compactMap { $0 }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .flatMap { directory in
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .contentTypeKey, .contentModificationDateKey,
                    ],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )) ?? []
            }
            .filter(matches)
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
    }

    static var userHomeDirectory: URL {
        guard let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir
        else {
            return .homeDirectory
        }

        return URL(
            fileURLWithFileSystemRepresentation: path,
            isDirectory: true,
            relativeTo: nil
        )
    }

    private static var standardDirectories: [URL] {
        let home = userHomeDirectory

        return [
            home,
            home.appending(path: "Desktop"),
            home.appending(path: "Documents"),
            home.appending(path: "Downloads"),
        ]
    }

    /// The offered places, led by whatever is currently selected so the button
    /// has a titled entry to show for it.
    private var options: [Location] {
        var urls: [URL] = []

        if let current = fileURL.wrappedValue {
            urls.append(current)
        }

        urls += recentURLs

        if !locations.isEmpty {
            urls += locations
        } else if canChooseDirectories {
            urls += [defaultDirectory].compactMap { $0 }
            urls += Self.standardDirectories
        }

        var seen = Set<String>()
        return urls.compactMap { url in
            seen.insert(url.standardizedFileURL.path).inserted
                ? Location(url: url) : nil
        }
    }

    private var actionTitle: String {
        options.isEmpty ? "Choose..." : "Other..."
    }

    private var selection: Binding<Location> {
        Binding {
            Location(url: fileURL.wrappedValue)
        } set: { location in
            fileURL.wrappedValue = location.url
            onSelection?()

            if let url = location.url {
                remember(url)
            }
        }
    }

    private func remember(_ url: URL) {
        guard let recents else { return }

        RecentLocations.remember(url, for: recents)
        recentURLs = RecentLocations.urls(for: recents)
    }

    private func title(for location: Location) -> String {
        guard let url = location.url else { return "" }

        switch label {
        case .name:
            let name = FileManager.default.displayName(atPath: url.path)
            return name.isEmpty ? url.lastPathComponent : name
        case .path:
            return location.description
        }
    }

    private var popUp: some View {
        FormPicker(
            placeholder: placeholder,
            options: options,
            selection: selection,
            actionTitle: actionTitle,
            onAction: selectFile,
            title: title(for:),
            icon: \.icon
        )
    }

    private var path: Binding<String> {
        Binding {
            fileURL.wrappedValue?.path ?? ""
        } set: { typed in
            let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)

            fileURL.wrappedValue =
                typed.isEmpty ? nil : URL(filePath: expanding(typed))
            onSelection?()
        }
    }

    /// A leading `~` means the person's home, which is not what
    /// `expandingTildeInPath` resolves to from inside the sandbox.
    private func expanding(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }

        return Self.userHomeDirectory.path + path.dropFirst()
    }

    private var field: some View {
        FormField(
            placeholder: placeholder,
            value: path,
            actionIcon: "folder",
            actionTitle: "Choose",
            action: selectFile
        )
    }

    var body: some View {
        Group {
            switch style {
            case .popUp:
                popUp
            case .field:
                field
            }
        }
        .onChange(of: isPresented?.wrappedValue ?? false) { _, isPresented in
            guard isPresented else { return }
            selectFile()
            self.isPresented?.wrappedValue = false
        }
        .task {
            guard style == .popUp, let recents else { return }
            recentURLs = RecentLocations.urls(for: recents)
        }
        .task(id: options.first) {
            guard style == .popUp, isEnabled, fileURL.wrappedValue == nil,
                let first = options.first?.url
            else { return }

            fileURL.wrappedValue = first
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
            remember(url)
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = !canChooseDirectories
        panel.canChooseDirectories = canChooseDirectories
        panel.canCreateDirectories = canCreateDirectories
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
        remember(url)
    }
}
