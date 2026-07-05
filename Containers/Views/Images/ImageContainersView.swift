//
//  ImageContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import Containerization
import ContainerizationError
import SwiftUI

struct ImageContainersView: View {
    let image: ImageViewModel?
    let volume: VolumeViewModel?

    @Environment(ContainerManager.self) private var containerManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var containers: [ContainerViewModel]
    @SwiftUI.State private var isLoading: Bool
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError = false

    init(image: ImageViewModel) {
        self.image = image
        self.volume = nil
        self._containers = State(initialValue: [])
        self._isLoading = State(initialValue: true)
    }

    init(volume: VolumeViewModel) {
        self.image = nil
        self.volume = volume
        self._containers = State(initialValue: [])
        self._isLoading = State(initialValue: true)
    }

    init(containers: [ContainerViewModel]) {
        self.image = nil
        self.volume = nil
        self._containers = State(initialValue: containers)
        self._isLoading = State(initialValue: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            content

            // Bottom bar
            Divider()

            HStack {
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
        .task(id: taskID) {
            guard taskID != nil else { return }
            await loadContainers()
        }
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") {
                    self.showError = false
                }
            },
            message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading containers...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if containers.isEmpty {
            ContentUnavailableView {
                Label("No Containers", systemImage: "cube.fill")
            } description: {
                Text("No containers are currently using this image")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(
                of: ContainerViewModel.self,
                columns: {
                    TableColumn("Name") { container in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(
                                    container.status == .running
                                        ? Color.green : Color.red
                                )
                                .frame(width: 6, height: 6)

                            Text(container.id)
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
                        Text(container.formattedState)
                            .font(.subheadline)
                            .foregroundStyle(
                                container.status == .running
                                    ? .primary : .secondary
                            )
                    }
                    .width(min: 64, ideal: 80, max: 100)

                },
                rows: {
                    ForEach(containers)
                }
            )
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
        }
    }

    private var title: String {
        if image != nil {
            return "Containers Using This Image"
        }
        return "Containers Using This Volume"
    }

    private var taskID: String? {
        image?.id ?? volume?.id
    }

    private var statusText: String {
        guard !isLoading else {
            return image?.imageDescription.reference ?? volume?.name ?? ""
        }

        return
            "\(containers.count) \(containers.count == 1 ? "container" : "containers")"
    }

    @MainActor
    private func loadContainers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshots = try await containerManager.list()

            if let image {
                self.containers =
                    snapshots
                    .filter {
                        $0.configuration.image.digest
                            == image.imageDescription.digest
                    }
                    .map(ContainerViewModel.init)
            } else if let volume {
                self.containers =
                    snapshots
                    .filter { $0.volumeNames.contains(volume.name) }
                    .map(ContainerViewModel.init)
            } else {
                self.containers = []
            }
        } catch {
            self.error = error
            self.showError = true
            self.containers = []
        }
    }
}
