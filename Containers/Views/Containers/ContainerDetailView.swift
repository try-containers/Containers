//
//  ContainerDetailView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ContainerDetailView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.close) private var close

    @SwiftUI.State private var container: ContainerViewModel
    @SwiftUI.State private var snapshot: ContainerSnapshot?
    @SwiftUI.State private var status: RuntimeStatus
    @SwiftUI.State private var selectedCategory: DetailCategory = .overview
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showAddVolumeMount: Bool = false
    @SwiftUI.State private var isLoadingSnapshot: Bool = false
    @SwiftUI.State private var isOperationInProgress: Bool = false

    enum DetailCategory: String, CaseIterable, Hashable {
        case overview
        case logs
        case inspect
    }

    init(
        container: ContainerViewModel,
        initialSnapshot: ContainerSnapshot? = nil
    ) {
        let initialContainer =
            initialSnapshot.map(ContainerViewModel.init) ?? container

        self._container = State(initialValue: initialContainer)
        self._snapshot = State(initialValue: initialSnapshot)
        self._status = State(initialValue: initialContainer.status)
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            onClose: close,
            header: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(container.id)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            },
            actionButtons: {
                actionButtons
            },
            tabTitle: { tab in
                tab.rawValue.localizedCapitalized
            },
            fixedHeightTab: { tab in
                tab != .overview
            },
            tabContent: { tab in
                switch tab {
                case .overview:
                    snapshotContent { snapshot in
                        ContainerOverview(snapshot: snapshot)
                    }
                case .inspect:
                    snapshotContent { snapshot in
                        ContainerInspect(snapshot: snapshot)
                    }
                case .logs:
                    ContainerLogs(containerID: container.id)
                }
            }
        )
        .task(id: container.id) {
            guard snapshot == nil else { return }
            await refreshSnapshot()
        }
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
        .modal(isPresented: $showAddVolumeMount) {
            AddVolumeMountView(
                containerID: container.id,
                existingMountDestinations: snapshot?.configuration.mounts.map(
                    \.destination
                ) ?? [],
                onMount: { volume, destination in
                    try await containerManager.mountVolume(
                        containerID: container.id,
                        volume: volume,
                        destination: destination
                    )
                    await refreshSnapshot()
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
                            ids: [container.id],
                            force: true
                        )

                        error = nil
                        close()
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
                await refreshSnapshot()
            }
        }
    }

    @ViewBuilder
    private func snapshotContent<Content: View>(
        @ViewBuilder content: (ContainerSnapshot) -> Content
    ) -> some View {
        if let snapshot {
            content(snapshot)
        } else if isLoadingSnapshot {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Container Details Unavailable",
                systemImage: "shippingbox",
                description: Text(
                    "The full container snapshot could not be loaded."
                )
            )
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
                    label: "Start",
                    icon: "play.fill",
                    help: "Start container"
                ) {
                    startContainer()
                }

                ActionButton(
                    label: "Add Volume",
                    icon: "externaldrive.badge.plus",
                    help: "Mount volume"
                ) {
                    showAddVolumeMount = true
                }
                .disabled(snapshot == nil)

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
            .foregroundStyle(Color.red)
            .disabled(isOperationInProgress)
        }
    }

    private func refreshSnapshot() async {
        isLoadingSnapshot = snapshot == nil
        defer {
            isLoadingSnapshot = false
        }

        do {
            let updatedSnapshot = try await containerManager.get(
                id: container.id
            )
            let updatedContainer = ContainerViewModel(updatedSnapshot)

            snapshot = updatedSnapshot
            container = updatedContainer
            status = updatedContainer.status
            error = nil
        } catch {
            self.error = error
            showError = true
        }
    }

    private func startContainer() {
        Task {
            isOperationInProgress = true

            defer {
                isOperationInProgress = false
            }

            do {
                try await containerManager.start(
                    id: container.id,
                    attachStdout: false,
                    attachStdin: false
                )

                error = nil
                await refreshSnapshot()

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
                    ids: [container.id],
                    timeoutSeconds: UserDefaults.stopContainerTimeoutSeconds
                )

                error = nil
                await refreshSnapshot()

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
                            mediaType:
                                "application/vnd.oci.image.manifest.v1+json",
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
        )
    )
    .frame(width: 550)
}
