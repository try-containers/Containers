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
    @State private var error: Error?
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var showCreateContainerView = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredContainers: [ContainerViewModel] {
        if trimmedText.isEmpty {
            return runningContainersOnly
                ? containers.filter({ $0.status == .running }) : containers
        }

        let filtered = self.containers.filter({
            $0.id.contains(trimmedText) == true
                || $0.imageName.contains(trimmedText)
                || $0.formattedPorts.contains(trimmedText) == true
                || $0.formattedIPAddress.contains(trimmedText) == true
        })

        return runningContainersOnly
            ? filtered.filter({ $0.status == .running }) : filtered
    }

    var body: some View {
        ListView(
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
                Text(container.formattedUptime)
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(
                        container.status == .running
                            ? .primary : .secondary
                    )
            }
            .width(min: 80, ideal: 100, max: 140)

            TableColumn("Actions") { container in
                HStack(spacing: 12) {
                    switch container.status {
                    case .running:
                        Button(
                            action: {
                                Task {
                                    do {
                                        try await containerManager.stop(
                                            ids: [container.id],
                                            timeoutSeconds: Int32(
                                                UserDefaults
                                                    .stopContainerTimeoutSeconds
                                            )
                                        )
                                    } catch (let err) {
                                        self.error = err
                                        self.showError = true
                                    }
                                }
                            },
                            label: {
                                Image(systemName: "stop.fill")
                                    .foregroundStyle(.gray)
                            }
                        )
                        .buttonStyle(.plain)

                    case .stopped:
                        Button(
                            action: {
                                Task {
                                    do {
                                        try await containerManager.run(
                                            id: container.id,
                                            attachStdout: false,
                                            attachStdin: false
                                        )
                                    } catch (let err) {
                                        self.error = err
                                        self.showError = true
                                    }
                                }
                            },
                            label: {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.blue)
                            }
                        )
                        .buttonStyle(.plain)

                    case .stopping, .unknown:
                        Image(systemName: "slash.circle")
                            .foregroundStyle(.secondary)
                    }

                    Button(
                        action: {
                            selectedContainer = container
                            showDeleteConfirmation = true
                        },
                        label: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                        }
                    )
                    .buttonStyle(.plain)
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
            "Delete Container?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let container = selectedContainer else {
                    return
                }

                Task {
                    do {
                        try await containerManager.delete(
                            ids: [container.id],
                            force: true
                        )
                        await refreshContainers()
                    } catch (let err) {
                        self.error = err
                        self.showError = true
                    }
                }

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

    private func refreshContainers() async {
        do {
            self.containers = (try await containerManager.list())
                .map({ ContainerViewModel($0) })
                .sorted { $0.id < $1.id }
            self.lastUpdated = Date()
        } catch (let err) {
            self.error = err
            self.showError = true
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
