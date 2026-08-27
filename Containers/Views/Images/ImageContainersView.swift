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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var containers: [ContainerViewModel]
    @SwiftUI.State private var isLoading: Bool
    @SwiftUI.State private var filterText: String = ""
    @SwiftUI.State private var hoveredID: String?
    @SwiftUI.State private var errorAlert: ErrorAlert?

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

    private var filteredContainers: [ContainerViewModel] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return containers }
        return containers.filter {
            $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterField(
                text: $filterText,
                cornerRadius: 15,
                horizontalPadding: 8,
                verticalPadding: 7,
                highlightsActiveFilter: false
            )
            .padding(8)

            content
        }
        .frame(width: 260)
        .task(id: taskID) {
            guard taskID != nil else { return }
            await loadContainers()
        }
        .errorAlert($errorAlert)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.bottom, 10)
        } else if filteredContainers.isEmpty {
            Text("No containers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.bottom, 10)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filteredContainers) { container in
                        Button {
                            dismiss()
                            openWindow(
                                id: ContainersApp.containerDetailWindowID,
                                value: container.id
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Text(container.id)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .foregroundStyle(
                                        hoveredID == container.id
                                            ? .white : .primary
                                    )

                                Text(
                                    container.status == .running
                                        ? "Running" : "Stopped"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    hoveredID == container.id
                                        ? .white
                                        : (container.status == .running
                                            ? Color.green : .secondary)
                                )
                                .frame(width: 56, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        hoveredID == container.id
                                            ? Color.accentColor : Color.clear
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveredID = $0 ? container.id : nil }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var taskID: String? {
        image?.id ?? volume?.id
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
            self.errorAlert = ErrorAlert(
                "The containers couldn’t be loaded.",
                error: error
            )
            self.containers = []
        }
    }
}
