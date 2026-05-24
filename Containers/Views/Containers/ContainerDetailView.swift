//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerSystem
import ContainerizationOCI
import SwiftUI
import Logging

struct ContainerDetailView: View {
    let onClose: () -> Void

    @Environment(ContainerManager.self) private var containerManager
    @Environment(VolumeManager.self) private var volumeManager

    @SwiftUI.State private var container: ContainerViewModel
    @SwiftUI.State private var status: RuntimeStatus
    @SwiftUI.State private var selectedCategory: DetailCategory = .inspect

    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showAddVolumeMount: Bool = false
    @SwiftUI.State private var isOperationInProgress: Bool = false

    enum DetailCategory: String, CaseIterable, Hashable {
        case inspect
        case logs
    }

    init(
        container: ContainerViewModel,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self._container = State(initialValue: container)
        self._status = State(initialValue: container.status)
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            onClose: onClose,
            header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(container.id)
                        .font(.title2)
                        .fontWeight(.semibold)

                    statusBadge
                }
            },
            actionButtons: {
                actionButtons
            },
            tabTitle: { tab in
                tab.rawValue.localizedCapitalized
            },
            tabContent: { tab in
                switch tab {
                case .inspect:
                    ContainerInspectView(container: container)

                case .logs:
                    ContainerLogsView(containerID: container.id)
                }
            }
        )
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") {
                    showError = false
                }
            },
            message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        )
        .sheet(isPresented: $showAddVolumeMount) {
            AddVolumeMountView(
                containerID: container.id,
                existingMountDestinations: container.snapshot.configuration.mounts.map(\.destination),
                onMount: { volume, destination in
                    try await containerManager.mountVolume(
                        containerID: container.id,
                        volume: volume,
                        destination: destination
                    )
                }
            )
            .environment(volumeManager)
        }
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

                        error = nil
                        onClose()
                    } catch {
                        self.error = error
                        showError = true
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

                    if let updatedSnapshot = containers.first(
                        where: { $0.configuration.id == container.id }
                    ) {
                        let updatedContainer = ContainerViewModel(updatedSnapshot)

                        if updatedContainer.status != status {
                            status = updatedContainer.status
                        }

                        container = updatedContainer
                    }
                } catch {
                    self.error = error
                    showError = true
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isOperationInProgress {
            ProgressView()
                .controlSize(.small)

        } else {
            switch status {
            case .running:
                ActionButton(
                    label: "Stop",
                    icon: "stop.fill",
                    help: "Stop container"
                ) {
                    stopContainer()
                }

            case .stopped:
                ActionButton(
                    label: "Add Volume",
                    icon: "externaldrive.badge.plus",
                    help: "Mount volume"
                ) {
                    showAddVolumeMount = true
                }

                ActionButton(
                    label: "Start",
                    icon: "play.fill",
                    help: "Start container"
                ) {
                    startContainer()
                }

            case .stopping:
                ProgressView()
                    .controlSize(.small)

            case .unknown:
                EmptyView()
            }

            ActionButton(
                label: "Delete",
                icon: "trash",
                help: "Delete container",
                role: .destructive
            ) {
                showDeleteConfirmation = true
            }
            .disabled(isOperationInProgress)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(
                    status == .running
                    ? Color.green
                    : Color.red
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
                    (
                        status == .running
                        ? Color.green
                        : Color.red
                    )
                    .opacity(0.1)
                )
        )
    }

    private func startContainer() {
        Task {
            isOperationInProgress = true

            defer {
                isOperationInProgress = false
            }

            do {
                try await containerManager.start(
                    id: container.snapshot.configuration.id,
                    attachStdout: false,
                    attachStdin: false
                )

                error = nil

            } catch {
                self.error = error
                showError = true
            }
        }
    }

    private func stopContainer() {
        Task {
            isOperationInProgress = true

            defer {
                isOperationInProgress = false
            }

            do {
                try await containerManager.stop(
                    snapshots: [container.snapshot],
                    timeoutSeconds: UserDefaults.stopContainerTimeoutSeconds
                )

                error = nil

            } catch {
                self.error = error
                showError = true
            }
        }
    }
}

#Preview {
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
    .frame(width: 800, height: 600)
}
