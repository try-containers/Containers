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

private struct PortsConfiguration: Identifiable {
    let id: UUID = UUID()
    var hostAddress: String = "127.0.0.1"
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp

    var publishedPort: PublishPort {
        let address = try? IPAddress(
            hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard let fallbackAddress = try? IPAddress("127.0.0.1") else {
            fatalError("Invalid fallback IP Addres")
        }

        return .init(
            hostAddress: address ?? fallbackAddress,
            hostPort: UInt16(self.host),
            containerPort: UInt16(self.container),
            proto: self.publishProtocol,
            count: 1
        )
    }
}

private struct VolumeConfiguration: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
    var path: String = ""
    var isAnonymous: Bool = false
}

private struct MountConfiguration: Identifiable {
    let id: UUID = UUID()
    var hostPath: String = ""
    var containerPath: String = ""
}

private struct CapabilityConfiguration: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
}

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

    private static let fieldWidth: CGFloat = 420

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
    @SwiftUI.State private var volumes: [VolumeConfiguration] = []
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
            onCancel: { dismiss() },
            tabBar: {
                CreateViewTabBar(selection: $selectedTab)
            },
            content: {
                tabContent
            },
            actions: {
                Button(mode.buttonTitle) {
                    createContainer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    imageReference.trimmingCharacters(
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
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
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
            HStack(alignment: .top) {
                Text("Image:")
                    .frame(
                        width: EditableFormLayout.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)

                Text(imageReference)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
                    .frame(width: Self.fieldWidth, alignment: .leading)
            }
        } else {
            EditableField(
                title: "Image",
                placeholder: "Select Image...",
                fieldWidth: Self.fieldWidth,
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
        VStack(alignment: .leading, spacing: 20) {
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
            VStack(alignment: .leading, spacing: 20) {
                EditableField(
                    title: "Entrypoint",
                    description: "Overrides the image's default entrypoint.",
                    placeholder: "/bin/sh -c \"echo hello\"",
                    value: Binding(
                        get: { container.entryPoint ?? "" },
                        set: { container.entryPoint = $0.isEmpty ? nil : $0 }
                    ),
                    fieldWidth: Self.fieldWidth
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
                    ),
                    fieldWidth: Self.fieldWidth
                )
            }
            .padding(20)

            Divider()

            EditableList(
                items: $environments,
                columnTitles: ["Environment Variables", "Value"],
                fieldWidth: Self.fieldWidth,
                addLabel: "Add Environment Variable",
                emptyMessage: "No Environment Variables",
                newItem: { KeyValue() },
                rowSummary: keyValueSummary,
                rowValues: { [$0.key, $0.value] },
                rowContent: { keyValue in
                    EditableListRowEdit(fields: [
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
                    ])
                },
                editorContent: { _ in
                    EmptyView()
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
            EditableField(
                title: "Platform",
                description:
                    "Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon.",
                placeholder: "Platform",
                fieldWidth: Self.fieldWidth,
                options: Self.platformOptions,
                selection: $platformString
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            EditableList(
                items: $volumes,
                title: "Volumes",
                editorDescription:
                    "Select an existing volume or create an anonymous volume. To create a new named volume, use the Volumes section.",
                columnTitles: ["Name", "Target"],
                fieldWidth: Self.fieldWidth,
                addLabel: "Add Volume",
                emptyMessage: "No Volumes",
                hasContentBelow: true,
                newItem: { VolumeConfiguration(name: availableVolumes.last?.name ?? "") },
                rowSummary: volumeMountSummary,
                rowValues: volumeMountValues,
                canSave: { volume in
                    !volume.path.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                },
                editorContent: { $volume in
                    VolumeRow(
                        volumeName: $volume.name,
                        path: $volume.path,
                        isAnonymous: $volume.isAnonymous,
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
                fieldWidth: Self.fieldWidth,
                addLabel: "Add Mount",
                emptyMessage: "No Mounts",
                hasContentBelow: true,
                newItem: { MountConfiguration() },
                rowSummary: mountSummary,
                rowValues: mountValues,
                canSave: { mount in
                    !mount.containerPath.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                },
                editorContent: { $mount in
                    MountRow(mount: $mount)
                }
            )
            .padding(.horizontal)

            EditableList(
                items: $ports,
                title: "Port Mappings",
                columnTitles: ["Host", "Container", "Protocol"],
                fieldWidth: Self.fieldWidth,
                addLabel: "Add Port Mapping",
                emptyMessage: "No Port Mappings",
                hasContentBelow: true,
                newItem: { PortsConfiguration() },
                rowSummary: portSummary,
                rowValues: portValues,
                editorContent: { $port in
                    PortMappingEditor(port: $port)
                }
            )
            .padding(.horizontal)

            EditableList(
                items: $capabilities,
                title: "Capabilities",
                columnTitles: ["Capability"],
                fieldWidth: Self.fieldWidth,
                addLabel: "Add Capability",
                emptyMessage: "No Capabilities",
                newItem: { CapabilityConfiguration() },
                rowSummary: capabilitySummary,
                rowValues: { [capabilitySummary($0)] },
                rowContent: { $capability in
                    EditableListRowEdit(fields: [
                        .init(
                            placeholder: "CAP_NET_ADMIN",
                            text: $capability.name
                        )
                    ])
                },
                editorContent: { _ in
                    EmptyView()
                }
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func capabilityNames(
        from capabilities: [CapabilityConfiguration]
    ) -> [String] {
        capabilities
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func capabilitySummary(_ capability: CapabilityConfiguration)
        -> String
    {
        capability.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func volumeMountSummary(_ volume: VolumeConfiguration) -> String {
        let name = volume.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = volume.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "Anonymous volume" : name

        return path.isEmpty ? displayName : "\(displayName) -> \(path)"
    }

    private func volumeMountValues(_ volume: VolumeConfiguration) -> [String] {
        let name = volume.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = volume.path.trimmingCharacters(in: .whitespacesAndNewlines)

        return [name.isEmpty ? "Anonymous volume" : name, path]
    }

    private func mountSummary(_ mount: MountConfiguration) -> String {
        let source = mount.hostPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let target = mount.containerPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if source.isEmpty && target.isEmpty {
            return "New Mount"
        }

        if source.isEmpty {
            return target.isEmpty
                ? "Temporary Mount" : "Temporary Mount -> \(target)"
        }

        return target.isEmpty ? source : "\(source) -> \(target)"
    }

    private func mountValues(_ mount: MountConfiguration) -> [String] {
        let source = mount.hostPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return [
            source.isEmpty ? "Temporary Mount" : source,
            mount.containerPath.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }

    private func portSummary(_ port: PortsConfiguration) -> String {
        "\(port.hostAddress):\(port.host):\(port.container)/\(port.publishProtocol.rawValue.uppercased())"
    }

    private func portValues(_ port: PortsConfiguration) -> [String] {
        [
            "\(port.hostAddress):\(port.host)",
            "\(port.container)",
            port.publishProtocol.rawValue.uppercased(),
        ]
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
                var validVolumeFSs: [Filesystem] = []
                var validBindMountFSs: [Filesystem] = []
                var validTmpfsFSs: [Filesystem] = []
                var mountDestinations = Set<String>()
                let mountOptions: [String] = []
                let existingVolumes = try await volumeManager.list()

                func reserveDestination(_ destination: String) -> Bool {
                    guard !mountDestinations.contains(destination) else {
                        return false
                    }
                    mountDestinations.insert(destination)
                    return true
                }

                for mount in self.mounts {
                    let source = mount.hostPath.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let destination = mount.containerPath.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let hasMountInput = !source.isEmpty || !destination.isEmpty

                    guard hasMountInput else {
                        continue
                    }

                    guard !destination.isEmpty else {
                        self.errorMessage = "Mounts require a target."
                        return
                    }

                    guard destination.hasPrefix("/") else {
                        self.errorMessage = "Mount target must be absolute."
                        return
                    }

                    guard reserveDestination(destination) else {
                        self.errorMessage =
                            "A mount already exists at \(destination)."
                        return
                    }

                    if source.isEmpty {
                        validTmpfsFSs.append(
                            .tmpfs(
                                destination: destination,
                                options: mountOptions
                            )
                        )
                        continue
                    }

                    let resolvedSource = (source as NSString)
                        .expandingTildeInPath
                    guard resolvedSource.hasPrefix("/") else {
                        self.errorMessage =
                            "Mount source must be an absolute host path."
                        return
                    }

                    validBindMountFSs.append(
                        .virtiofs(
                            source: resolvedSource,
                            destination: destination,
                            options: mountOptions
                        )
                    )
                }

                for volumeConfig in self.volumes {
                    let trimmedName = volumeConfig.name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let destination = volumeConfig.path.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let hasMountInput =
                        !trimmedName.isEmpty || !destination.isEmpty

                    guard hasMountInput else {
                        continue
                    }

                    guard destination.hasPrefix("/") else {
                        self.errorMessage = "Volume target must be absolute."
                        return
                    }

                    guard reserveDestination(destination) else {
                        self.errorMessage =
                            "A mount already exists at \(destination)."
                        return
                    }

                    let volume: Volume
                    if let existingVolume = existingVolumes.first(where: {
                        $0.name == trimmedName
                    }) {
                        volume = existingVolume
                    } else {
                        var volumeName = trimmedName
                        var labels: [KeyValue] = []

                        if volumeName.isEmpty {
                            volumeName =
                                VolumeStorage.generateAnonymousVolumeName()
                            labels.append(.init(key: Volume.anonymousLabel))
                        }

                        volume = try await volumeManager.create(
                            name: volumeName,
                            labels: labels,
                            options: [],
                            sizeInBytes: nil
                        )
                    }

                    let fs = Filesystem.volume(
                        name: volume.name,
                        format: volume.format,
                        source: volume.source,
                        destination: destination,
                        options: mountOptions
                    )

                    validVolumeFSs.append(fs)
                }

                self.container.virtualFileSystem = validBindMountFSs
                self.container.temporaryFileSystem = validTmpfsFSs
                self.container.volumes = validVolumeFSs
                self.container.platform = try Platform(
                    from: self.platformString
                )
                self.container.shmSize =
                    self.shmSizeInMiB > 0
                    ? UInt64(self.shmSizeInMiB) * 1024 * 1024 : nil
                self.container.capabilities = Self.capabilityNames(
                    from: self.capabilities
                )

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
                    try await containerManager.start(id: containerID)
                }

                dismiss()

            } catch (let error) {
                self.errorMessage = "\(error)"
            }

            self.showProgressView = false
        }
    }
}

private struct PortMappingEditor: View {
    @Binding var port: PortsConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Host Address", text: $port.hostAddress)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Host Port", value: $port.host, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField(
                    "Container Port",
                    value: $port.container,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
            }

            Picker("Protocol", selection: $port.publishProtocol) {
                Text("TCP").tag(PublishProtocol.tcp)
                Text("UDP").tag(PublishProtocol.udp)
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct MountRow: View {
    @Binding var mount: MountConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Source").font(.caption).foregroundStyle(.secondary)
                EditableField(
                    placeholder: "/Users/me/project",
                    value: $mount.hostPath,
                    fieldWidth: .infinity,
                    actionLabel: {
                        Label("Browse", systemImage: "folder").labelStyle(.iconOnly)
                    },
                    action: browseFolder
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target (Required)").font(.caption).foregroundStyle(.secondary)
                EditableField(
                    placeholder: "/workspace",
                    value: $mount.containerPath,
                    fieldWidth: .infinity
                )
            }
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            mount.hostPath = url.path
        }
    }
}

private struct VolumeRow: View {
    @Binding var volumeName: String
    @Binding var path: String
    @Binding var isAnonymous: Bool
    let availableVolumes: [Volume]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Anonymous volume", isOn: $isAnonymous)
                .toggleStyle(.checkbox)
                .onChange(of: isAnonymous) { _, anonymous in
                    if anonymous { volumeName = "" }
                }

            if !isAnonymous {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Volume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Volume", selection: $volumeName) {
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
                Text("Target (Required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("/data", text: $path)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
