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
    @SwiftUI.State private var isAnonymous: Bool = false
    @SwiftUI.State private var isMounting: Bool = false
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

                Toggle("Anonymous volume", isOn: $isAnonymous)
                    .toggleStyle(.checkbox)
                    .onChange(of: isAnonymous) { _, anonymous in
                        if anonymous { volumeName = "" }
                    }

                if !isAnonymous {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume").font(.caption).foregroundStyle(.secondary)
                        Picker("Volume", selection: $volumeName) {
                            if volumeName.isEmpty {
                                Text("Select a volume...").tag("")
                            }
                            ForEach(availableVolumes, id: \.name) { volume in
                                Text(volume.name).tag(volume.name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Target").font(.caption).foregroundStyle(.secondary)
                    TextField("/data", text: $mountPath)
                        .textFieldStyle(.roundedBorder)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            HStack {
                if isMounting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Mounting volume...")
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
        .task {
            availableVolumes = (try? await volumeManager.list()) ?? []
            if let last = availableVolumes.last {
                volumeName = last.name
            }
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

                if let existing = volumes.first(where: { $0.name == trimmedName }) {
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
