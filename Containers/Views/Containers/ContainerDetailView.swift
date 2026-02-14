//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerResource
import ContainerSystem
import ContainerizationOCI
import SwiftUI
import Logging

struct ContainerDetailView: View {
    let onClose: () -> Void
    
    @Environment(ContainerManager.self) private var containerManager
 
    @SwiftUI.State private var container: ContainerViewModel
    @SwiftUI.State private var status: RuntimeStatus
    @SwiftUI.State private var selectedCategory: DetailCategory = .inspect
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var isOperationInProgress: Bool = false
    
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
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self._container = SwiftUI.State(initialValue: container)
        self._status = SwiftUI.State(initialValue: container.status)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(container.id)
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
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        if isOperationInProgress {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            switch status {
                            case .running:
                                Button {
                                    Task {
                                        isOperationInProgress = true
                                        do {
                                            try await containerManager.stop(
                                                snapshots: [container.snapshot],
                                                timeoutSeconds: UserDefaults.stopContainerTimeoutSeconds
                                            )
                                            
                                            self.error = nil
                                        } catch (let error) {
                                            self.error = error
                                            self.showError = true
                                        }
                                        isOperationInProgress = false
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
                                        isOperationInProgress = true
                                        do {
                                            try await containerManager.start(
                                                id: container.snapshot.configuration.id,
                                                attachStdout: false,
                                                attachStdin: false
                                            )
                                            
                                            self.error = nil
                                        } catch (let error) {
                                            self.error = error
                                            self.showError = true
                                        }
                                        isOperationInProgress = false
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
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .help("Delete container")
                        .disabled(isOperationInProgress)
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
                        
                        self.error = nil
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
                "Are you sure you want to delete container '\(container.id)'? This action cannot be undone."
            )
        }
        .onChange(of: containerManager.lastContainerChange) {
            Task {
                do {
                    let containers = try await containerManager.list()
                    
                    if let updatedSnapshot = containers.first(where: { $0.configuration.id == container.id }) {
                        let updatedContainer = ContainerViewModel(updatedSnapshot)
                        
                        if updatedContainer.status != status {
                            status = updatedContainer.status
                        }
                        
                        container = updatedContainer
                    }
                } catch {
                    self.error = error
                    self.showError = true
                }
            }
        }
    }
}

#Preview {
    @Previewable @SwiftUI.State var containerManager = ContainerManager()
    
    ContainerDetailView(
        container: ContainerViewModel(
            ContainerSnapshot(
                configuration: ContainerConfiguration(
                    id: "preview-container",
                    image: ImageDescription(
                        reference: "nginx:latest",
                        descriptor: ContainerizationOCI.Descriptor(
                            mediaType: "application/vnd.oci.image.manifest.v1+json",
                            digest: "sha256:1234567890abcdef",
                            size: 1024
                        )
                    ),
                    process: ProcessConfiguration(
                        executable: "/bin/sh",
                        arguments: [],
                        environment: [],
                        workingDirectory: "/",
                        terminal: false
                    )
                ),
                status: .running,
                networks: [],
                startedDate: Date()
            )
        ),
        onClose: {}
    )
    .environment(containerManager)
    .frame(width: 800, height: 600)
}
