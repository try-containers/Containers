//
//  ContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import SwiftUI

struct ContainersView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(SystemManager.self) private var system
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.openWindow) private var openWindow

    @Binding var searchText: String
    @Binding var runningContainersOnly: Bool

    var refreshTrigger: Int

    @State private var containers: [ContainerViewModel] = []
    @State private var selectedContainer: ContainerViewModel? = nil
    @State private var lastUpdated: Date? = nil
    @State private var errorAlert: ErrorAlert?
    @State private var showDeleteConfirmation = false
    @State private var showCreateContainerView = false
    @State private var runningContainerIDs: Set<String> = []

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredContainers: [ContainerViewModel] {
        if trimmedText.isEmpty {
            return marked(
                runningContainersOnly
                    ? containers.filter({ $0.status == .running }) : containers
            )
        }

        let filtered = self.containers.filter({
            $0.id.contains(trimmedText) == true
                || $0.imageName.contains(trimmedText)
                || $0.formattedPorts.contains(trimmedText) == true
                || $0.formattedIPAddress.contains(trimmedText) == true
        })

        return marked(
            runningContainersOnly
                ? filtered.filter({ $0.status == .running }) : filtered
        )
    }

    /// Says which rows are working, so that a row whose buttons have to change
    /// is a row the table can see has changed.
    private func marked(
        _ containers: [ContainerViewModel]
    ) -> [ContainerViewModel] {
        containers.map { container in
            var container = container
            container.isBusy = runningContainerIDs.contains(container.id)
            return container
        }
    }

    var body: some View {
        TableView(
            rows: filteredContainers,
            refreshTrigger: refreshTrigger,
            lastUpdated: lastUpdated,
            isFiltering: !trimmedText.isEmpty || runningContainersOnly,
            tableStyle: .automatic,
            onClear: {
                containers = []
                lastUpdated = nil
            },
            onRefresh: refreshContainers
        ) {
            TableColumn("Name") { container in
                Button(
                    action: {
                        openWindow(
                            id: ContainersApp.containerDetailWindowID,
                            value: container.id
                        )
                    },
                    label: {
                        Text(container.name)
                            .lineLimit(1)
                            .underline()
                    }
                )
                .buttonStyle(.link)
                .pointerStyle(.link)
            }
            .width(min: 100, ideal: 150, max: 250)

            TableColumn("Image") { container in
                Text(container.imageName)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180, max: 300)

            TableColumn("State") { container in
                Text(container.status.rawValue.localizedCapitalized)
                    .foregroundStyle(stateColor(for: container.status))
                    .lineLimit(1)
            }
            .width(min: 64, ideal: 80, max: 100)

            TableColumn("IP Address") { container in
                Text(container.formattedIPAddress)
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(
                        !container.hasIPAddress
                            ? .secondary : .primary
                    )
                    .textSelection(.enabled)
            }
            .width(min: 100, ideal: 120, max: 140)

            TableColumn("Uptime") { container in
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(container.formattedUptime(at: context.date))
                        .lineLimit(1)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(
                            container.status == .running
                                ? .primary : .secondary
                        )
                }
            }
            .width(min: 80, ideal: 100, max: 140)

            TableColumn("Actions") { container in
                HStack(spacing: 12) {
                    switch container.status {
                    case .running:
                        RowActionButton(
                            icon: "stop.fill",
                            tint: .gray,
                            isEnabled: !container.isBusy
                        ) {
                            stopContainer(container)
                        }

                    case .stopped:
                        RowActionButton(
                            icon: "play.fill",
                            tint: .blue,
                            isEnabled: !container.isBusy
                        ) {
                            startContainer(container)
                        }

                    case .stopping, .unknown:
                        Image(systemName: "slash.circle")
                            .foregroundStyle(.secondary)
                    }

                    // Only the actions answer for the work: the row stays
                    // live, so its detail is a click away while it runs.
                    RowActionButton(
                        icon: "trash.fill",
                        tint: .red,
                        isEnabled: !container.isBusy
                    ) {
                        selectedContainer = container
                        showDeleteConfirmation = true
                    }
                }
                .padding(.horizontal, 8)
            }
            .width(min: 92, ideal: 92, max: 92)
        }
        .onChange(of: containerManager.lastContainerChange) {
            Task {
                guard system.status == .running else { return }
                await refreshContainers()
            }
        }
        .sheet(
            isPresented: $showCreateContainerView,
            onDismiss: {
                Task {
                    await refreshContainers()
                }
            },
            content: {
                CreateContainerView(imageReference: "")
            }
        )
        .errorAlert($errorAlert)
        .confirmationDialog(
            "Delete Container?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let container = selectedContainer else {
                    return
                }

                deleteContainer(container)
                selectedContainer = nil
            }

            Button("Cancel", role: .cancel) {
                selectedContainer = nil
            }
        } message: {
            if let container = selectedContainer {
                Text("Delete \(container.id)? This cannot be undone.")
            }
        }
    }

    private func stateColor(for status: ContainerStatus) -> Color {
        switch status {
        case .running: return .green
        case .stopping: return .orange
        case .stopped: return .red
        case .unknown: return .secondary
        }
    }

    private func startContainer(_ container: ContainerViewModel) {
        runningContainerIDs.insert(container.id)

        Task {
            defer { runningContainerIDs.remove(container.id) }

            do {
                try await containerManager.run(id: container.id)
            } catch (let err) {
                self.errorAlert = ErrorAlert(
                    "The container couldn’t be started.",
                    error: err
                )
            }
        }
    }

    private func stopContainer(_ container: ContainerViewModel) {
        runningContainerIDs.insert(container.id)

        Task {
            defer { runningContainerIDs.remove(container.id) }

            do {
                try await containerManager.stop(
                    ids: [container.id],
                    timeoutSeconds: Int32(
                        UserDefaults.stopContainerTimeoutSeconds
                    )
                )
            } catch (let err) {
                self.errorAlert = ErrorAlert(
                    "The container couldn’t be stopped.",
                    error: err
                )
            }
        }
    }

    private func deleteContainer(_ container: ContainerViewModel) {
        runningContainerIDs.insert(container.id)

        Task {
            defer { runningContainerIDs.remove(container.id) }

            do {
                try await containerManager.delete(
                    ids: [container.id],
                    force: true
                )
                await refreshContainers()
            } catch (let err) {
                self.errorAlert = ErrorAlert(
                    "The container couldn’t be deleted.",
                    error: err
                )
            }
        }
    }

    private func refreshContainers() async {
        do {
            self.containers = (try await containerManager.list())
                .map({ ContainerViewModel($0) })
                .sorted { $0.id < $1.id }
            self.lastUpdated = Date()
        } catch (let err) {
            self.errorAlert = ErrorAlert(
                "The containers couldn’t be loaded.",
                error: err
            )
        }
    }
}

#Preview {
    ContainersView(
        searchText: .constant(""),
        runningContainersOnly: .constant(false),
        refreshTrigger: 0
    )
    .environment(ContainerManager())
    .environment(SystemManager())
}
