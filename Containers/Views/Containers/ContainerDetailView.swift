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

struct ContainerDetailWindow: View {
    @Environment(ContainerManager.self) private var containerManager

    let id: String

    @SwiftUI.State private var snapshot: ContainerSnapshot?
    @SwiftUI.State private var isLoading: Bool = true
    @SwiftUI.State private var loadError: Error?
    @SwiftUI.State private var toolbarController = DetailToolbarController()

    var body: some View {
        Group {
            if let snapshot {
                ContainerDetailView(
                    container: ContainerViewModel(snapshot),
                    initialSnapshot: snapshot,
                    toolbarController: toolbarController
                )
            } else if isLoading {
                // Empty until the detail arrives; the window grows into it.
                Color.clear
                    .frame(
                        width: DetailPlaceholder.container.width,
                        height: DetailPlaceholder.container.height
                    )
            } else {
                ContentUnavailableView(
                    "Container Not Found",
                    systemImage: "shippingbox",
                    description: Text(
                        loadError?.localizedDescription
                            ?? "The container '\(id)' no longer exists."
                    )
                )
                .frame(width: 550, height: 320)
            }
        }
        .background(
            DetailToolbarAttacher(
                controller: toolbarController,
                tabs: ContainerDetailView.toolbarTabs,
                actions: ContainerDetailView.placeholderActions
            )
        )
        .navigationTitle(id)
        .task(id: id) {
            await load()
        }
    }

    private func load() async {
        isLoading = true

        defer { isLoading = false }

        do {
            snapshot = try await containerManager.get(id: id)
            loadError = nil
        } catch {
            snapshot = nil
            loadError = error
        }
    }
}

struct ContainerDetailView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismissWindow) private var dismissWindow

    @SwiftUI.State private var container: ContainerViewModel
    @SwiftUI.State private var snapshot: ContainerSnapshot?
    @SwiftUI.State private var status: ContainerStatus
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

    let toolbarController: DetailToolbarController

    init(
        container: ContainerViewModel,
        initialSnapshot: ContainerSnapshot? = nil,
        toolbarController: DetailToolbarController = DetailToolbarController()
    ) {
        self.toolbarController = toolbarController

        let initialContainer =
            initialSnapshot.map(ContainerViewModel.init) ?? container

        self._container = State(initialValue: initialContainer)
        self._snapshot = State(initialValue: initialSnapshot)
        self._status = State(initialValue: initialContainer.status)
    }

    var body: some View {
        DetailView(
            selectedTab: $selectedCategory,
            actions: actions,
            tabTitle: { tab in
                tab.rawValue.localizedCapitalized
            },
            tabIcon: { Self.tabIcon($0) },
            tabMaxHeight: { tab in
                switch tab {
                case .overview: nil
                case .logs: 560
                case .inspect: 500
                }
            },
            tabContentWidth: { tab in
                switch tab {
                case .overview: DetailPlaceholder.width
                case .logs, .inspect: nil
                }
            },
            toolbarController: toolbarController,
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
        .sheet(isPresented: $showAddVolumeMount) {
            MountVolumeSheet(
                existingMountDestinations: snapshot?.configuration.mounts.map(
                    \.destination
                ) ?? [],
                onMount: mountVolume
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
                        dismissWindow(
                            id: ContainersApp.containerDetailWindowID,
                            value: container.id
                        )
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

    private func mountVolume(_ draft: VolumeMount) async {
        do {
            let volume = try await volumeManager.volume(
                named: draft.source == .anonymousVolume
                    ? "" : draft.trimmedVolumeName,
                among: try await volumeManager.list()
            )

            try await containerManager.mountVolume(
                id: container.id,
                volume: volume,
                destination: draft.trimmedTarget
            )

            await refreshSnapshot()
        } catch {
            self.error = error
            showError = true
        }
    }

    private func snapshotContent<Content: View>(
        @ViewBuilder content: (ContainerSnapshot) -> Content
    ) -> some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else if isLoadingSnapshot {
                // Hidden by the window until ready, so nothing to draw.
                Color.clear
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
        // Outermost, or the window cannot read it. A failed load is still a
        // result to be sized to, so only the fetch itself counts as unready.
        .contentReady(!isLoadingSnapshot || snapshot != nil)
    }

    /// A fixed set, in a fixed order: the toolbar is built from these ids
    /// before the snapshot arrives, and a set that changed with the status
    /// would rebuild the toolbar — items visibly popping in — the moment it
    /// did. Only what the buttons do and whether they are enabled varies.
    private var actions: [DetailAction] {
        let busy = isOperationInProgress
        let isRunning = status == .running
        let isStopped = status == .stopped

        return [
            DetailAction(
                id: "run",
                title: isRunning ? "Stop" : "Start",
                icon: isRunning ? "stop.fill" : "play.fill",
                help: isRunning ? "Stop container" : "Start container",
                isEnabled: !busy && (isRunning || isStopped)
            ) {
                if isRunning {
                    stopContainer()
                } else {
                    runContainer()
                }
            },
            DetailAction(
                id: "add-volume",
                title: "Add Volume",
                icon: "externaldrive.badge.plus",
                help: "Mount volume",
                isEnabled: !busy && isStopped && snapshot != nil
            ) {
                showAddVolumeMount = true
            },
            DetailAction(
                id: "delete",
                title: "Delete",
                icon: "trash",
                help: "Delete container",
                isEnabled: !busy,
                isDestructive: true
            ) {
                showDeleteConfirmation = true
            },
        ]
    }

    /// The same shape with nothing wired up, so the window can build its
    /// toolbar before it has a container to build one from.
    static var placeholderActions: [DetailAction] {
        [
            DetailAction(
                id: "run",
                title: "Start",
                icon: "play.fill",
                isEnabled: false
            ) {},
            DetailAction(
                id: "add-volume",
                title: "Add Volume",
                icon: "externaldrive.badge.plus",
                isEnabled: false
            ) {},
            DetailAction(
                id: "delete",
                title: "Delete",
                icon: "trash",
                isEnabled: false,
                isDestructive: true
            ) {},
        ]
    }

    static var toolbarTabs: [DetailToolbarController.Tab] {
        DetailCategory.allCases.map {
            .init(title: $0.rawValue.localizedCapitalized, icon: tabIcon($0))
        }
    }

    static func tabIcon(_ tab: DetailCategory) -> String {
        switch tab {
        case .overview: "info.circle"
        case .logs: "list.bullet.rectangle"
        case .inspect: "curlybraces"
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

    private func runContainer() {
        Task {
            isOperationInProgress = true

            defer {
                isOperationInProgress = false
            }

            do {
                try await containerManager.run(
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

private struct MountVolumeSheet: View {
    let existingMountDestinations: [String]
    let onMount: (VolumeMount) async -> Void

    @Environment(VolumeManager.self) private var volumeManager

    @SwiftUI.State private var mount = VolumeMount()
    @SwiftUI.State private var availableVolumes: [Volume] = []

    var body: some View {
        FormSheet(
            title: "Mount Volume",
            description:
                "Select an existing volume or create an anonymous volume.",
            primaryButtonTitle: "Mount",
            showsCancelButton: true,
            isPrimaryButtonDisabled: !canMount,
            onSave: { Task { await onMount(mount) } }
        ) {
            VolumeEditor(mount: $mount, availableVolumes: availableVolumes)
        }
        .task {
            availableVolumes = (try? await volumeManager.list()) ?? []
            mount.volumeName = availableVolumes.last?.name ?? ""
            mount.source =
                availableVolumes.isEmpty ? .anonymousVolume : .volume
        }
    }

    private var canMount: Bool {
        let target = mount.trimmedTarget
        return target.hasPrefix("/")
            && !existingMountDestinations.contains(target)
    }
}
