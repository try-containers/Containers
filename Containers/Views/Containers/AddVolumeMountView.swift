//
//  AddVolumeView.swift
//  Containers
//
//  Created by Axel Martinez on 23/5/26.
//

import ContainerSystem
import SwiftUI

struct AddVolumeMountView: View {
    let containerID: String
    let existingMountDestinations: [String]
    let onMount: (Volume, String) async throws -> Void

    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var volumeName: String = ""
    @SwiftUI.State private var mountPath: String = ""
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var showVolumePicker = false
    @SwiftUI.State private var isLoadingVolumes = false
    @SwiftUI.State private var isMounting = false
    @SwiftUI.State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mount Volume")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(containerID)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Volume")
                        .font(.headline)
                    Text(
                        "Choose an existing volume, enter a new volume name, or leave empty to create an anonymous volume. Mounts and tmpfs are configured when creating a container."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("my-volume", text: $volumeName)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            loadVolumesAndShowPicker()
                        } label: {
                            Label("Choose", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Choose from existing volumes")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target")
                        .font(.headline)
                    Text(
                        "The absolute path where the volume will be mounted inside the container."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    TextField("/data", text: $mountPath)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            HStack {
                if isLoadingVolumes || isMounting {
                    ProgressView()
                        .controlSize(.small)
                    Text(
                        isMounting ? "Mounting volume..." : "Loading volumes..."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isMounting)

                Button("Mount") {
                    mountVolume()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isMounting
                        || mountPath.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 520, height: 420)
        .sheet(isPresented: $showVolumePicker) {
            VolumeSelectionView(
                volumes: availableVolumes,
                onVolumeSelect: { selectedName in
                    volumeName = selectedName
                }
            )
        }
    }

    private func loadVolumesAndShowPicker() {
        Task {
            isLoadingVolumes = true
            errorMessage = nil
            do {
                availableVolumes = try await volumeManager.list()
                showVolumePicker = true
            } catch {
                errorMessage = "\(error)"
            }
            isLoadingVolumes = false
        }
    }

    private func mountVolume() {
        let trimmedName = volumeName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let destination = mountPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard destination.hasPrefix("/") else {
            errorMessage =
                "Volume mount path must be an absolute container path."
            return
        }

        guard !existingMountDestinations.contains(destination) else {
            errorMessage = "A mount already exists at \(destination)."
            return
        }

        Task {
            isMounting = true
            errorMessage = nil
            do {
                let volumes = try await volumeManager.list()
                let volume: Volume

                if let existing = volumes.first(where: {
                    $0.name == trimmedName
                }) {
                    volume = existing
                } else {
                    var name = trimmedName
                    var labels: [KeyValue] = []
                    if name.isEmpty {
                        name = VolumeStorage.generateAnonymousVolumeName()
                        labels.append(.init(key: Volume.anonymousLabel))
                    }
                    volume = try await volumeManager.create(
                        name: name,
                        labels: labels,
                        options: [],
                        sizeInBytes: nil
                    )
                }

                try await onMount(volume, destination)
                dismiss()
            } catch {
                errorMessage = "\(error)"
            }
            isMounting = false
        }
    }
}
