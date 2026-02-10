//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerResource
import ContainerSystem
import SwiftUI

struct ContainerDetailView: View {
    let container: ContainerViewModel
    let onStart: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    
    @Environment(ContainerManager.self) private var containerManager
 
    @State private var status: RuntimeStatus
    @State private var selectedCategory: DetailCategory = .inspect
    @State private var error: Error?
    @State private var showError: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    enum DetailCategory: String, Identifiable {
        case logs
        case inspect
        
        var id: String {
            return self.rawValue
        }
        
        static let allCases: [DetailCategory] = [.inspect, .logs]
    }
    
    init(
        container: ContainerViewModel,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.container = container
        self.onStart = onStart
        self.onStop = onStop
        self.onClose = onClose
        self.status = container.status
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
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
                                    .fill(
                                        status == .running
                                        ? Color.green : Color.red
                                    )
                                    .frame(width: 8, height: 8)
                                Text(status.rawValue.localizedCapitalized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        (status == .running
                                         ? Color.green : Color.red).opacity(
                                            0.1
                                         )
                                    )
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
                                Label(
                                    container.formattedIPAddress,
                                    systemImage: "network"
                                )
                                .font(
                                    .system(.subheadline, design: .monospaced)
                                )
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        switch status {
                        case .running:
                            Button {
                                Task {
                                    do {
                                        try await containerManager.stop(
                                            snapshots: [container.snapshot],
                                            timeoutSeconds: UserDefaults.stopContainerTimeoutSeconds
                                        )
                                        
                                        status = .stopped
                                        
                                        onStop()
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
                                        
                                        status = .running
                                        
                                        onStart()
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
            Picker(
                selection: $selectedCategory,
                content: {
                    ForEach(DetailCategory.allCases) { category in
                        Text(category.rawValue.localizedCapitalized)
                            .tag(category)
                    }
                },
                label: {}
            )
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
                    ContainerInspectView(container: container)
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
            
        }
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") {
                    self.showError = false
                }
            },
            message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
        )
        .confirmationDialog(
            "Delete Container",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await containerManager.delete(
                            snapshots: [container.snapshot],
                            force: true
                        )
                        
                        onClose()
                    } catch (let error) {
                        self.error = error
                        self.showError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Are you sure you want to delete container '\(container.name)'? This action cannot be undone."
            )
        }
    }
}

/*#Preview {
    ContainerDetailView(container: ContainerViewModel(
        snapshot: ContainerSnapshot(from: any Decoder),
        onClose: () -> {})
    )
}*/
