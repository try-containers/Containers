//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import SwiftUI

struct CreateContainerView: View {
    enum Mode {
        case create
        case run

        var title: String {
            switch self {
            case .create:
                "Create New Container"
            case .run:
                "Run Container"
            }
        }

        var progressTitle: String {
            switch self {
            case .create:
                "Creating container..."
            case .run:
                "Running container..."
            }
        }

        var buttonTitle: String {
            switch self {
            case .create:
                "Create"
            case .run:
                "Run"
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info"
        case process = "Process"
        case options = "Options"

        var id: String { rawValue }
    }

    @Environment(ContainerManager.self) private var containerManager
    @Environment(ImageManager.self) private var imageManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @SwiftUI.State var imageReference: String

    @SwiftUI.State private var process: ContainerProcess = .init()
    @SwiftUI.State private var container: ContainerInfo = .init()
    @SwiftUI.State private var volumes: [VolumeMountConfiguration] = []
    @SwiftUI.State private var mounts: [MountConfiguration] = []
    @SwiftUI.State private var ports: [PortsConfiguration] = []
    @SwiftUI.State private var environments: [KeyValue] = []
    @SwiftUI.State private var resource: ContainerConfiguration.Resources =
        .init()
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto
        .rawValue
    @SwiftUI.State private var platformString: String = Platform.current
        .description
    @SwiftUI.State private var shmSizeInMiB: Int = 0
    @SwiftUI.State private var capabilities: [CapabilityConfiguration] = []
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var selectedTab: Tab = .info

    init(imageReference: String, mode: Mode = .create) {
        self.mode = mode
        self._imageReference = State(initialValue: imageReference)
    }

    var body: some View {
        CreateView(
            title: mode.title,
            errorMessage: $errorMessage,
            isProcessing: showProgressView,
            progressTitle: mode.progressTitle,
            width: 660,
            height: 460,
            scrollsContent: selectedTab == .options,
            contentPadding: selectedTab == .info ? 20 : 0,
            tabBar: {
                CreateViewTabBar(selection: $selectedTab)
            },
            content: {
                tabContent
            },
            actions: {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Button {
                    createContainer()
                } label: {
                    Text(mode.buttonTitle)
                        .frame(width: .sheetButtonLabelWidth)
                }
                .defaultAction(
                    enabled: !imageReference.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            },
            progress: {
                if !containerManager.progressMessage.isEmpty {
                    Text(containerManager.progressMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        )
        .sheet(
            isPresented: $showPickLocalImage,
            content: {
                ItemPicker(
                    title: "Choose Image",
                    actionTitle: "Choose",
                    items: self.localImages.map {
                        Item(id: $0.digest, label: $0.reference)
                    },
                    onSelect: { self.imageReference = $0.label }
                )
            }
        )
        .task {
            await preloadLocalImages()
            await preloadVolumes()
        }
        .onDisappear {
            self.showProgressView = false
        }
    }

    private static var platformOptions: [String] {
        let current = Platform.current
        var options = [current.description]

        if current.architecture == "arm64" {
            options.append("linux/amd64")
        }

        return options
    }

    @ViewBuilder
    private var imageSelectionField: some View {
        if mode == .run {
            HStack(alignment: .firstTextBaseline) {
                Text("Image:")

                Text(imageReference)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fieldControl()
            }
        } else {
            EditableField(
                title: "Image",
                placeholder: "Select Image...",
                options: localImages.map { $0.reference },
                selection: $imageReference,
                selectionActionTitle: "Other...",
                onSelectionAction: { showPickLocalImage = true }
            )
        }
    }

    private func preloadLocalImages() async {
        guard localImages.isEmpty else { return }
        localImages = (try? await imageManager.list().map(\.description)) ?? []
        if imageReference.isEmpty, let first = localImages.first {
            imageReference = first.reference
        }
    }

    private func showLocalImageSelection() {
        guard localImages.isEmpty else {
            showPickLocalImage = true
            return
        }
        Task {
            do {
                showProgressView = true
                localImages = try await imageManager.list().map(\.description)
                showProgressView = false
                showPickLocalImage = true
            } catch (let error) {
                showProgressView = false
                errorMessage = "\(error)"
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            infoTab
        case .process:
            processTab
        case .options:
            optionsTab
        }
    }

    private var infoTab: some View {
        FieldStack {
            imageSelectionField

            EditableField(
                title: "Name",
                description:
                    "Leave empty to generate a unique name automatically.",
                placeholder: "my-container",
                value: $container.name
            )
        }
    }

    private var processTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldStack {
                EditableField(
                    title: "Entrypoint",
                    description: "Overrides the image's default entrypoint.",
                    placeholder: "/bin/sh -c \"echo hello\"",
                    value: Binding(
                        get: { container.entryPoint ?? "" },
                        set: { container.entryPoint = $0.isEmpty ? nil : $0 }
                    )
                )

                EditableField(
                    title: "Stop Signal",
                    placeholder: "SIGTERM",
                    value: Binding(
                        get: { container.stopSignal ?? "" },
                        set: {
                            container.stopSignal =
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty ? nil : $0
                        }
                    )
                )
            }
            .padding(20)

            Divider()

            EditableList(
                items: $environments,
                columnTitles: ["Environment Variables", "Value"],
                addLabel: "Add Environment Variable",
                emptyMessage: "No Environment Variables",
                newItem: { KeyValue() },
                rowFields: { keyValue in
                    [
                        .init(
                            placeholder: "Key",
                            text: keyValue.key,
                            isMonospaced: true
                        ),
                        .init(
                            placeholder: "Value",
                            text: keyValue.value,
                            isMonospaced: true
                        ),
                    ]
                }
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var optionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldStack {
                EditableField(
                    title: "Platform",
                    description:
                        "Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon.",
                    placeholder: "Platform",
                    options: Self.platformOptions,
                    selection: $platformString
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            EditableList(
                items: $volumes,
                title: "Volumes",
                editorDescription:
                    "Select an existing volume or create an anonymous volume. To create a new named volume, use the Volumes section.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Volume",
                emptyMessage: "No Volumes",
                hasContentBelow: true,
                newItem: {
                    VolumeMountConfiguration(
                        source: availableVolumes.isEmpty
                            ? .anonymousVolume : .volume,
                        volumeName: availableVolumes.last?.name ?? ""
                    )
                },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: { !$0.trimmedTarget.isEmpty },
                editorContent: { $volume in
                    VolumeEditor(
                        mount: $volume,
                        availableVolumes: availableVolumes
                    )
                }
            )
            .padding(.horizontal)

            EditableList(
                items: $mounts,
                title: "Mounts",
                editorDescription:
                    "Share a host path with the container. Leave Source empty to create a temporary in-memory mount.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Mount",
                emptyMessage: "No Mounts",
                hasContentBelow: true,
                newItem: { MountConfiguration() },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: { !$0.trimmedTarget.isEmpty },
                editorContent: { $mount in
                    MountEditor(mount: $mount)
                }
            )
            .padding(.horizontal)

            EditableList(
                items: $ports,
                title: "Port Mappings",
                editorDescription:
                    "Publish a container port on the host, so it can be reached from outside the container.",
                columnTitles: ["Host", "Container", "Protocol"],
                addLabel: "Add Port Mapping",
                emptyMessage: "No Port Mappings",
                hasContentBelow: true,
                newItem: { PortsConfiguration() },
                rowSummary: \.summary,
                rowValues: \.columns,
                editorContent: { $port in
                    PortEditor(port: $port)
                }
            )
            .padding(.horizontal)

            EditableList(
                items: $capabilities,
                title: "Capabilities",
                columnTitles: ["Capability"],
                addLabel: "Add Capability",
                emptyMessage: "No Capabilities",
                newItem: { CapabilityConfiguration() },
                rowFields: { $capability in
                    [
                        .init(
                            placeholder: "CAP_NET_ADMIN",
                            text: $capability.name
                        )
                    ]
                }
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preloadVolumes() async {
        guard availableVolumes.isEmpty else { return }
        availableVolumes = (try? await volumeManager.list()) ?? []
    }

    private func createContainer() {
        let trimmedReference = imageReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedReference.isEmpty else {
            self.errorMessage = "Image is not specified."
            return
        }

        Task {
            self.showProgressView = true

            do {
                let mounts = try await ContainerMountPlanner.plan(
                    mounts: self.mounts,
                    volumes: self.volumes,
                    volumeManager: volumeManager
                )

                self.container.virtualFileSystem = mounts.bindMounts
                self.container.temporaryFileSystem = mounts.temporaryFileSystems
                self.container.volumes = mounts.volumes
                self.container.platform = try Platform(
                    from: self.platformString
                )
                self.container.shmSize =
                    self.shmSizeInMiB > 0
                    ? UInt64(self.shmSizeInMiB) * 1024 * 1024 : nil
                self.container.capabilities = self.capabilities.names

                let validPorts = self.ports.filter({
                    $0.host > 0 && $0.container > 0
                })

                self.container.publishPorts = validPorts.map(\.publishedPort)

                let validEnvironments = self.environments.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && !$0.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                })

                self.process.environments = validEnvironments.map { kv in
                    "\(kv.key)=\(kv.value)"
                }

                // Make copies for actor boundary crossing
                let process = self.process
                let container = self.container
                let resource = self.resource
                let registryScheme = self.registryScheme

                let containerID = try await containerManager.create(
                    imageReference: trimmedReference,
                    imagesDir: UserDefaults.applicationDataRoot
                        .appendingPathComponent("images"),
                    arguments: [],
                    process: process,
                    container: container,
                    resource: resource,
                    registryScheme: registryScheme
                )

                if mode == .run {
                    try await containerManager.run(id: containerID)
                }

                dismiss()

            } catch (let error) {
                self.errorMessage = "\(error)"
            }

            self.showProgressView = false
        }
    }
}
