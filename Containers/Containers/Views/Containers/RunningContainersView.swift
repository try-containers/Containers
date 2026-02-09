//
//  RunningContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem
import ContainerizationError
import ContainerResource

struct RunningContainersView: View {
    var containers: [ContainerViewModel]
    var updateContainer: (String) async throws -> Void
    var deleteContainer: (String)-> Void

    @Environment(ContainerManager.self) private var containerManager
    @Environment(\.dismiss) private var dismiss

    @State private var showProgressView: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var containerToDelete: ContainerViewModel?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Containers Using This Image")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(containers.count) \(containers.count == 1 ? "container" : "containers")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Table
            if containers.isEmpty {
                ContentUnavailableView {
                    Label("No Containers", systemImage: "cube")
                } description: {
                    Text("No containers are currently using this image")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(of: ContainerViewModel.self, columns: {
                    TableColumn("Name") { container in
                        HStack(spacing: 8) {
                            // Status indicator
                            Circle()
                                .fill(container.status == .running ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            
                            Text(container.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .frame(height: 40)
                    }
                    .width(min: 120, ideal: 180, max: 300)
                    
                    TableColumn("Image") { container in
                        Text(container.imageName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 160, max: 250)
                    
                    TableColumn("State") { container in
                        HStack(spacing: 4) {
                            Text(container.formattedState)
                                .font(.subheadline)
                                .foregroundStyle(container.status == .running ? .primary : .secondary)
                        }
                    }
                    .width(min: 64, ideal: 80, max: 100)
                    
                    TableColumn("Actions") { container in
                        HStack(spacing: 8) {
                            switch container.status {
                            case .running:
                                Button {
                                    Task {
                                        await stopContainer(container)
                                    }
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Stop container")
                                
                            case .stopped:
                                Button {
                                    Task {
                                        await startContainer(container)
                                    }
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Start container")
                                
                            case .stopping:
                                ProgressView()
                                    .controlSize(.small)
                                
                            case .unknown:
                                EmptyView()
                            }
                            
                            Button(role: .destructive) {
                                containerToDelete = container
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Delete container")
                        }
                        .padding(.horizontal, 4)
                    }
                    .width(min: 100, ideal: 120, max: 120)
                    
                }, rows: {
                    ForEach(containers)
                })
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
            }
            
            // Bottom bar
            Divider()
            
            HStack {
                if showProgressView {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    dismiss()
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
        .frame(width: 600, height: 500)
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            Text(self.errorMessage ?? "Unknown Error")
        })
        .confirmationDialog(
            "Delete Container",
            isPresented: Binding(
                get: { containerToDelete != nil },
                set: { if !$0 { containerToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let container = containerToDelete {
                    Task {
                        await deleteContainerAction(container)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                containerToDelete = nil
            }
        } message: {
            if let container = containerToDelete {
                Text("Are you sure you want to delete container '\(container.name)'? This action cannot be undone.")
            }
        }
        .onChange(of: self.errorMessage, initial: false) {
            if errorMessage != nil {
                self.showProgressView = false
                self.showError = true
            }
        }
        .onChange(of: self.showError, initial: false) {
            if !showError {
                self.errorMessage = nil
            }
        }
    }
    
    // MARK: - Actions
    
    private func stopContainer(_ container: ContainerViewModel) async {
        showProgressView = true
        
        do {
            try await containerManager.stop(
                snapshots: [container.snapshot],
                timeoutSeconds: Int32(UserDefaults.stopContainerTimeoutSeconds)
            )
            
            try await self.updateContainer(container.id)
            
            showProgressView = false
        } catch {
            self.errorMessage = "\(error)"
            showProgressView = false
        }
    }
    
    private func startContainer(_ container: ContainerViewModel) async {
        showProgressView = true
        
        do {
            try await containerManager.start(
                id: container.snapshot.configuration.id,
                attachStdout: false,
                attachStdin: false
            )
            
            try await self.updateContainer(container.id)
            
            showProgressView = false
        } catch {
            self.errorMessage = "\(error)"
            showProgressView = false
        }
    }
    
    private func deleteContainerAction(_ container: ContainerViewModel) async {
        showProgressView = true
        
        do {
            try await containerManager.delete(snapshots: [container.snapshot], force: true)
            
            self.deleteContainer(container.id)
            showProgressView = false
            containerToDelete = nil
        } catch {
            self.errorMessage = "\(error)"
            showProgressView = false
        }
    }
}
