//
//  MountEditor.swift
//  Containers
//
//  Created by Axel Martinez on 04/08/2026.
//

import AppKit
import SwiftUI

struct MountEditor: View {
    @Binding var mount: Mount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FormField(
                    placeholder: "/Users/me/project",
                    value: $mount.hostPath,
                    actionIcon: "folder",
                    actionTitle: "Browse",
                    action: browseFolder
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target (Required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FormField(
                    placeholder: "/workspace",
                    value: $mount.containerPath
                )
            }
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            mount.hostPath = url.path
        }
    }
}
