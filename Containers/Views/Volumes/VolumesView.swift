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
    @Environment(SystemManager.self) private var system

    @Binding var searchText: String
    var refreshTrigger: Int

    @State private var volumes: [VolumeViewModel] = []
    @State private var lastUpdated: Date? = nil
    @State private var showInUseContainerForVolume: VolumeViewModel?
    @State private var selectedVolume: VolumeViewModel?
    @State private var showVolumeDetail: Bool = false
    @State private var showCreateVolumeView: Bool = false
    @State private var error: Error?
    @State private var showError: Bool = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredVolumes: [VolumeViewModel] {
        if trimmedText.isEmpty {
            return volumes
        }
        let filtered = self.volumes.filter({
            $0.name.contains(trimmedText)
        })

        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if system.isRunning {
                Table(
                    of: VolumeViewModel.self,
                    columns: {

                        TableColumn("Name") { volume in
                            Button(
                                action: {
                                    selectedVolume = volume
                                    showVolumeDetail = true
                                },
                                label: {
                                    Text(volume.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .underline()
                                }
                            )
                            .buttonStyle(.link)
                            .pointerStyle(.link)
                            .frame(height: 32)
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
                                Text("(Not Specified")
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
                                Button(
                                    action: {
                                        Task {
                                            do {
                                                try await volumeManager.delete(
                                                    volumes: [volume.volume])

                                                await self.listVolumes()
                                            } catch (let err) {
                                                self.error = err
                                                self.showError = true
                                            }
                                        }
                                    },
                                    label: {
                                        Image(systemName: "trash.fill")
                                            .foregroundStyle(
                                                volume.inUse
                                                    ? .secondary : Color.red
                                            )
                                    }
                                )
                                .disabled(volume.inUse)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                        }
                        .width(80)

                    },
                    rows: {
                        ForEach(filteredVolumes)
                    }
                )
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .overlay(
                    alignment: .center,
                    content: {
                        if filteredVolumes.isEmpty {
                            ContentUnavailableView(
                                trimmedText.isEmpty
                                    ? "No Volumes Found"
                                    : "No Matching Volumes",
                                systemImage: NavigationTab.volumes.icon
                            )
                        }
                    }
                )
            } else {
                ContainerSystemView()
            }
        }
        .onChange(
            of: self.system.isRunning,
            initial: true,
            {
                guard self.system.isRunning else {
                    self.volumes = []
                    self.lastUpdated = nil
                    return
                }

                Task {
                    guard self.lastUpdated == nil else {
                        return
                    }
                    await self.listVolumes()
                }
            }
        )
        .onChange(of: refreshTrigger) {
            Task {
                await self.listVolumes()
            }
        }
        .onAppear {
            Task {
                guard system.isRunning else { return }
                await self.listVolumes()
            }
        }
        .modal(
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
        .modal(
            isPresented: $showVolumeDetail,
            onDismiss: {
                selectedVolume = nil
            }
        ) {
            if let volume = selectedVolume {
                VolumeDetailView(volume: volume)
            }
        }
        .modal(
            item: $showInUseContainerForVolume,
            content: { volume in
                ImageContainersView(volume: volume)
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
            self.error = err
            self.showError = true
        }
    }
}
