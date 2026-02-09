//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem
import ContainerResource

struct ContainerDetailView: View {
    var containerID: String
    var onClose: () -> Void

    @Environment(ContainerManager.self) private var containerManager

    @State private var container: ContainerViewModel?
    @State private var selectedCategory: DetailCategory = .inspect
    @State private var error: Error?
    @State private var showError: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    private let leftColumnWidth: CGFloat = 240
    
    enum DetailCategory: String, Identifiable {
        case logs
        case inspect
        
        var id: String {
            return self.rawValue
        }
        
        static let allCases: [DetailCategory] = [.inspect, .logs]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let container = container {
                // Header Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(container.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                // Status badge
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(container.status == .running ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(container.formattedState)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill((container.status == .running ? Color.green : Color.red).opacity(0.1))
                                )
                            }
                            
                            // Container ID
                            Text(container.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            
                            // Image and IP
                            HStack(spacing: 12) {
                                Label(container.imageName, systemImage: "cube")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                if container.hasIPAddress {
                                    Label(container.formattedIPAddress, systemImage: "network")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.blue)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Action Buttons
                        HStack(spacing: 8) {
                            switch container.status {
                            case .running:
                                Button {
                                    Task {
                                        do {
                                            try await containerManager.stop(
                                                snapshots: [container.snapshot],
                                                timeoutSeconds: Int32(UserDefaults.stopContainerTimeoutSeconds)
                                            )
                                            await self.getContainerInfo()
                                        } catch (let error) {
                                            self.error = error
                                            self.showError = true
                                        }
                                    }
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                                .help("Stop container")
                                
                            case .stopped:
                                Button {
                                    Task {
                                        do {
                                            try await containerManager.start(
                                                id: container.snapshot.configuration.id,
                                                attachStdout: false,
                                                attachStdin: false
                                            )
                                            await self.getContainerInfo()
                                        } catch (let error) {
                                            self.error = error
                                            self.showError = true
                                        }
                                    }
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderedProminent)
                                .help("Start container")
                                
                            case .stopping:
                                ProgressView()
                                    .controlSize(.small)
                                
                            case .unknown:
                                EmptyView()
                            }
                            
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .help("Delete container")
                        }
                    }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                // Tab Picker
                Picker(selection: $selectedCategory, content: {
                    ForEach(DetailCategory.allCases) { category in
                        Text(category.rawValue.localizedCapitalized)
                            .tag(category)
                    }
                }, label: {})
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                Divider()
                
                // Content Section
                Group {
                    switch self.selectedCategory {
                    case .logs:
                        ContainerLogsView(containerID: container.id)
                    case .inspect:
                        self.containerInspectView(container)
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Bottom bar with close button
                Divider()
                
                HStack {
                    Spacer()
                    
                    Button {
                        onClose()
                    } label: {
                        Text("Close")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading container details...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await self.getContainerInfo()
        }
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        })
        .confirmationDialog(
            "Delete Container",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        if let container = container {
                            try await containerManager.delete(snapshots: [container.snapshot], force: true)
                            onClose()
                        }
                    } catch (let error) {
                        self.error = error
                        self.showError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let container = container {
                Text("Are you sure you want to delete container '\(container.name)'? This action cannot be undone.")
            }
        }
    }
    
    private func getContainerInfo() async {
        do {
            let snapshot = try await containerManager.get(id: self.containerID)
            
            self.container = ContainerViewModel(snapshot)
        } catch(let error) {
            self.error = error
            self.showError = true
        }
    }
    
    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func emptyStateView(text: String) -> some View {
        HStack {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    @ViewBuilder private func containerInspectView(_ container: ContainerViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20, content: {
                let environments = KeyValue.fromEnvironment(container.snapshot)
                let ports = KeyValue.fromPorts(container.snapshot)
                
                // Environment Section
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Environment Variables", subtitle: nil)
                    
                    if environments.isEmpty {
                        emptyStateView(text: "No environment variables")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(environments) { env in
                                HStack {
                                    Text(env.key)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(width: self.leftColumnWidth, alignment: .leading)
                                    
                                    Text("=")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(env.value)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Ports Section
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Port Mappings", subtitle: nil)
                    
                    if ports.isEmpty {
                        emptyStateView(text: "No port mappings")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(ports) { port in
                                HStack {
                                    Label(port.key, systemImage: "network")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(width: self.leftColumnWidth, alignment: .leading)
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    
                                    Text(port.value)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Volumes Section
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Volumes", subtitle: nil)
                    
                    let volumeFSs = container.snapshot.volumeFSs
                    if volumeFSs.isEmpty {
                        emptyStateView(text: "No volumes mounted")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(0..<volumeFSs.count, id: \.self) { index in
                                let fileSystem: Filesystem = volumeFSs[index]
                                if let name = fileSystem.volumeName {
                                    HStack {
                                        Label(name, systemImage: "internaldrive")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(width: self.leftColumnWidth, alignment: .leading)
                                        
                                        let fileURL = URL(filePath: fileSystem.source)
                                        
                                        HStack(spacing: 8) {
                                            Text("\(fileSystem.source) → \(fileSystem.destination)")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            Button {
                                                self.openFile(fileURL)
                                            } label: {
                                                Image(systemName: "arrow.up.forward.square")
                                                    .font(.body)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Open in Finder")
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            })
            .padding(20)
        }
    }
    
    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absoluteString,
            inFileViewerRootedAtPath: url.parent.absoluteString
        )
    }
}

private struct ContainerLogsView: View {
    var containerID: String

    @Environment(ContainerManager.self) private var containerManager

    @State private var logs: String = ""
    @State private var error: Error?
    @State private var showError: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if logs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs Available", systemImage: "doc.text")
                } description: {
                    Text("Logs will appear here when the container generates output")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(logs)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .padding(20)
            }
        }
        .task {
            await self.getLogs()
        }
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        })
    }
    
    private func getLogs() async {
        do {
            let containerDir = UserDefaults.applicationDataRoot
                .appendingPathComponent("containers")
                .appendingPathComponent(containerID)
            
            self.logs = try await containerManager.getLog(
                id: containerID,
                containerDir: containerDir,
                boot: false
            )
        } catch(let error) {
            self.error = error
            self.showError = true
        }
    }
}

#Preview {
    /*ContainerDetailView(containerID: "a260263f-f5ab-4ad0-85bb-3b4c6f0e2f20")
     .environment(Runtime())
     .frame(minWidth: 400, minHeight: 300)*/
    
}
