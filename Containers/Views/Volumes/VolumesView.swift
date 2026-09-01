//
//  VolumeListView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import SwiftUI

struct VolumesView: View {
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.openWindow) private var openWindow
    @Binding var searchText: String
    var refreshTrigger: Int

    @State private var volumes: [VolumeViewModel] = []
    @State private var lastUpdated: Date? = nil
    @State private var showInUseContainerForVolume: VolumeViewModel?
    @State private var volumeToDelete: VolumeViewModel?
    @State private var showCreateVolumeView: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var errorAlert: ErrorAlert?
    @State private var busyVolumeIDs: Set<String> = []

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredVolumes: [VolumeViewModel] {
        if trimmedText.isEmpty {
            return marked(volumes)
        }
        let filtered = self.volumes.filter({
            $0.name.contains(trimmedText)
        })

        return marked(filtered)
    }

    /// Says which rows are working, so that a row whose buttons have to change
    /// is a row the table can see has changed.
    private func marked(_ volumes: [VolumeViewModel]) -> [VolumeViewModel] {
        volumes.map { volume in
            var volume = volume
            volume.isBusy = busyVolumeIDs.contains(volume.id)
            return volume
        }
    }

    var body: some View {
        TableView(
            rows: filteredVolumes,
            refreshTrigger: refreshTrigger,
            lastUpdated: lastUpdated,
            isFiltering: !trimmedText.isEmpty,
            onClear: {
                volumes = []
                lastUpdated = nil
            },
            onRefresh: listVolumes
        ) {
            TableColumn("Name") { volume in
                Button(
                    action: {
                        openWindow(
                            id: ContainersApp.volumeDetailWindowID,
                            value: volume.id
                        )
                    },
                    label: {
                        Text(volume.name)
                            .lineLimit(1)
                            .underline()
                    }
                )
                .buttonStyle(.link)
                .pointerStyle(.link)
            }
            .width(min: 80, ideal: 80)

            TableColumn("Type") { volume in
                Text(volume.volumeType.rawValue)
            }
            .width(80)

            TableColumn("State") { volume in
                Group {
                    if volume.inUse {
                        Button(
                            action: {
                                showInUseContainerForVolume = volume
                            },
                            label: {
                                Text("In use")
                                    .lineLimit(1)
                                    .underline()
                            }
                        )
                        .buttonStyle(.link)
                        .pointerStyle(.link)
                        .popover(
                            isPresented: Binding(
                                get: { showInUseContainerForVolume?.id == volume.id },
                                set: { if !$0 { showInUseContainerForVolume = nil } }
                            ),
                            arrowEdge: .bottom
                        ) {
                            ImageContainersView(volume: volume)
                        }
                    } else {
                        Text("Unused")
                    }
                }
                .lineLimit(1)
            }
            .width(64)

            TableColumn("Size") { volume in
                if let size = volume.formattedSize {
                    Text(size)
                } else {
                    Text("Not Specified")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 80, max: 120)

            TableColumn("Created") { volume in
                Text(volume.formattedCreated)
            }
            .width(min: 80, ideal: 80, max: 160)

            TableColumn("Actions") { volume in
                HStack(spacing: 12) {
                    // A volume a container is holding is not the row's to
                    // delete, whatever else the row is doing.
                    RowActionButton(
                        icon: "trash.fill",
                        tint: .red,
                        isEnabled: !volume.isBusy && !volume.inUse
                    ) {
                        volumeToDelete = volume
                        showDeleteConfirmation = true
                    }
                    .help("Delete volume")
                }
                .padding(.horizontal, 8)
            }
            .width(80)
        }
        .sheet(
            isPresented: $showCreateVolumeView,
            onDismiss: {
                Task {
                    await self.listVolumes()
                }
            },
            content: {
                CreateVolumeView()
            }
        )
        .errorAlert($errorAlert)
        .confirmationDialog(
            "Delete Volume?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let volume = volumeToDelete else {
                    return
                }

                deleteVolume(volume)
                volumeToDelete = nil
            }

            Button("Cancel", role: .cancel) {
                volumeToDelete = nil
            }
        } message: {
            if let volume = volumeToDelete {
                Text("Delete \(volume.name)? This cannot be undone.")
            }
        }
    }

    private func deleteVolume(_ volume: VolumeViewModel) {
        busyVolumeIDs.insert(volume.id)

        Task {
            defer { busyVolumeIDs.remove(volume.id) }

            do {
                try await volumeManager.delete(volumes: [volume.volume])
                await self.listVolumes()
            } catch (let err) {
                self.errorAlert = ErrorAlert(
                    "The volume couldn’t be deleted.",
                    error: err
                )
            }
        }
    }

    func listVolumes() async {
        do {
            let displayModels: [VolumeViewModel] =
                try await volumeManager.listWithUsage()
                .map(VolumeViewModel.init)
                .sorted { $0.name < $1.name }

            self.volumes = displayModels
            self.lastUpdated = Date()

        } catch (let err) {
            self.errorAlert = ErrorAlert(
                "The volumes couldn’t be loaded.",
                error: err
            )
        }
    }
}
