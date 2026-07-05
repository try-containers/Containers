//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
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
}

private struct MountConfiguration: Identifiable {
    let id: UUID = UUID()
    var hostPath: String = ""
    var containerPath: String = ""
}

private struct VolumePickerTarget: Identifiable {
    let id = UUID()
    let onVolumeSelect: (String) -> Void
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
                "Create Container"
            case .run:
                "Run Container"
            }
        }
    }

    private static let fieldWidth: CGFloat = 420

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
    @SwiftUI.State private var volumeInitialized: Bool = false
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var volumePickerTarget: VolumePickerTarget?
    @SwiftUI.State private var isProcessOptionsExpanded: Bool = false
    @SwiftUI.State private var isManagementOptionsExpanded: Bool = false

    init(imageReference: String, mode: Mode = .create) {
        self.mode = mode
        self._imageReference = State(initialValue: imageReference)
    }

    var body: some View {
        CreateView(
            title: mode.title,
            errorMessage: $errorMessage,
            isWorking: showProgressView,
            progressTitle: mode.progressTitle,
            width: 660,
            height: 560,
            scrollsContent: true,
            onCancel: { dismiss() },
            content: {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        imageSelectionField

                        EditableField(
                            title: "Name",
                            description:
                                "Leave empty to generate a unique name automatically.",
                            placeholder: "my-container",
                            value: $container.name,
                            fieldWidth: Self.fieldWidth
                        )
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    processOptions
                    managementOptions
                }
            },
            actions: {
                Button(mode.buttonTitle) {
                    createContainer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
                ImageSelectionView(
                    images: self.localImages,
                    onImageSelect: {
                        self.imageReference = $0
                    }
                )
            }
        )
        .sheet(
            item: $volumePickerTarget,
            content: { target in
                VolumeSelectionView(
                    volumes: self.availableVolumes,
                    onVolumeSelect: { selectedName in
                        target.onVolumeSelect(selectedName)
                    }
                )
            }
        )
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
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

    private var imageSelectionField: some View {
        HStack(alignment: .top) {
            Text("Image:")
                .frame(
                    width: EditableFormLayout.labelWidth,
                    alignment: .trailing
                )
                .padding(.top, EditableFormLayout.fieldLabelTopPadding)

            HStack(spacing: 8) {
                Text(
                    imageReference.isEmpty
                        ? "No image selected" : imageReference
                )
                .foregroundStyle(imageReference.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .stroke(Color(nsColor: .separatorColor))
                }

                Button {
                    showLocalImageSelection()
                } label: {
                    Label("Choose", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Choose an existing image")
            }
            .frame(width: Self.fieldWidth, alignment: .leading)
        }
    }

    private func showLocalImageSelection() {
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

    private var processOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            collapsibleOptionsHeader(
                title: "Process Options",
                isExpanded: $isProcessOptionsExpanded
            )

            if isProcessOptionsExpanded {
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

                EditableList(
                    items: $environments,
                    title: "Environment Variables",
                    columnTitles: ["Key", "Value"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Environment Variable",
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
        }
    }

    private var managementOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            collapsibleOptionsHeader(
                title: "Management Options",
                isExpanded: $isManagementOptionsExpanded
            )

            if isManagementOptionsExpanded {
                EditableField(
                    title: "Platform",
                    description:
                        "Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon.",
                    placeholder: "Platform",
                    fieldWidth: Self.fieldWidth,
                    options: Self.platformOptions,
                    selection: $platformString
                )

                // Volumes
                EditableList(
                    items: $volumes,
                    title: "Volumes",
                    editorDescription:
                        "Use an existing volume, enter a new volume name, or leave Volume empty to create an anonymous volume.",
                    columnTitles: ["Volume", "Target"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Volume",
                    newItem: { VolumeConfiguration() },
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
                            showAvailableVolume: {
                                showAvailableVolumes {
                                    volume.name = $0
                                }
                            }
                        )
                    }
                )

                EditableList(
                    items: $mounts,
                    title: "Mounts",
                    editorDescription:
                        "Share a host path with the container. Leave Source empty to create a temporary in-memory mount.",
                    columnTitles: ["Source", "Target"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Mount",
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

                // Ports
                EditableList(
                    items: $ports,
                    title: "Port Mappings",
                    columnTitles: ["Host", "Container", "Protocol"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Port Mapping",
                    newItem: { PortsConfiguration() },
                    rowSummary: portSummary,
                    rowValues: portValues,
                    editorContent: { $port in
                        PortMappingEditor(port: $port)
                    }
                )

                EditableList(
                    items: $capabilities,
                    title: "Capabilities",
                    columnTitles: ["Capability"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Capability",
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
            }
        }
    }

    private func collapsibleOptionsHeader(
        title: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName: isExpanded.wrappedValue
                        ? "chevron.down" : "chevron.right"
                )
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)

                Text(title)
                    .font(.headline)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func showAvailableVolumes(
        onVolumeSelect: @escaping (String) -> Void
    ) {
        guard !self.volumeInitialized else {
            self.volumePickerTarget = VolumePickerTarget(
                onVolumeSelect: onVolumeSelect
            )
            return
        }

        Task {
            do {
                self.showProgressView = true
                self.availableVolumes = try await volumeManager.list()
                self.showProgressView = false
                self.volumeInitialized = true
                self.volumePickerTarget = VolumePickerTarget(
                    onVolumeSelect: onVolumeSelect
                )
            } catch (let error) {
                self.showProgressView = false
                self.errorMessage = "\(error)"
            }
        }
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
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("/Users/me/project", text: $mount.hostPath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target (Required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("/workspace", text: $mount.containerPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct VolumeRow: View {
    @Binding var volumeName: String
    @Binding var path: String

    var showAvailableVolume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("my-volume", text: $volumeName)
                        .textFieldStyle(.roundedBorder)
                    Button(
                        action: {
                            self.showAvailableVolume()
                        },
                        label: {
                            Label("Choose", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    )
                    .buttonStyle(.borderless)
                    .help("Choose from existing volumes")
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
