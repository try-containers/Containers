//
//  SettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import SwiftUI
import ContainerSystem

struct SettingsView: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(SystemManager.self) private var system

    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var storageLocation = UserDefaults.applicationDataRoot
    @State private var dnsDomains: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Configure application preferences")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    storageLocationSection
                    dnsDomainsSection
                }
                .padding(20)
            }
            .frame(maxWidth: 600)
        }
        .task {
            storageLocation = UserDefaults.applicationDataRoot
            dnsDomains = networkManager.listDomains()
        }
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                showError = false
            }
        }, message: {
            Text(errorMessage ?? "Unknown Error")
        })
        .onChange(of: errorMessage) {
            if errorMessage != nil {
                showError = true
            }
        }
        .onChange(of: showError) {
            if !showError {
                errorMessage = nil
            }
        }
    }

    private var storageLocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Storage Location")
                    .font(.headline)
            } icon: {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.blue)
            }

            Text("Containers, images, volumes, kernels, and build data are stored in this folder. Changes take effect the next time the container system starts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(storageLocation.lastPathComponent)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(storageLocation.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if system.isRunning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Stop the container system before changing the storage location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button(action: chooseStorageLocation) {
                    Label("Choose Folder", systemImage: "folder.badge.gearshape")
                }
                .disabled(system.isRunning)

                Button(action: resetStorageLocation) {
                    Text("Use Default")
                }
                .disabled(system.isRunning || UserDefaults.usesDefaultApplicationDataRoot)

                Spacer()
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var dnsDomainsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("DNS Domains")
                    .font(.headline)
            } icon: {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
            }

            Text("DNS domains let containers access host services. Inside a container, reach the host via the domain name (e.g., host.containers.internal:8000).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if dnsDomains.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No domains configured.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(dnsDomains, id: \.self) { domain in
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.blue)

                                Text(domain)
                                    .font(.system(.body, design: .monospaced))
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("DNS domain management requires administrator privileges. To manage domains, manually create files in /etc/resolver/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = storageLocation
        panel.prompt = "Choose"
        panel.message = "Choose where Containers stores containers, images, volumes, kernels, and build data."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            UserDefaults.setApplicationDataRoot(url, bookmarkData: bookmarkData)
            storageLocation = UserDefaults.applicationDataRoot
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetStorageLocation() {
        UserDefaults.resetApplicationDataRoot()
        storageLocation = UserDefaults.applicationDataRoot
    }
}

#Preview {
    SettingsView()
        .environment(NetworkManager())
        .environment(SystemManager())
}
