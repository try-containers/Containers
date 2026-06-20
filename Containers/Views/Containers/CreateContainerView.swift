//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import ContainerizationExtras
import ContainerizationOCI
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
        let fallbackAddress = try! IPAddress("127.0.0.1")

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

private struct VolumePickerTarget: Identifiable {
    let id: UUID
}

private struct CapabilityConfiguration: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
}

struct CreateContainerView: View {
    private static let fieldWidth: CGFloat = 420

    @Environment(ContainerManager.self) private var containerManager
    @Environment(ImageManager.self) private var imageManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.close) private var close

    @SwiftUI.State var imageReference: String

    @SwiftUI.State private var process: ContainerProcess = .init()
    @SwiftUI.State private var container: ContainerInfo = .init()
    @SwiftUI.State private var volumes: [VolumeConfiguration] = []
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
    @SwiftUI.State private var showErrorPopover: Bool = false
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var volumeInitialized: Bool = false
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var volumePickerTarget: VolumePickerTarget?
    @SwiftUI.State private var isProcessOptionsExpanded: Bool = true
    @SwiftUI.State private var isManagementOptionsExpanded: Bool = true

    init(imageReference: String) {
        self._imageReference = State(initialValue: imageReference)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Container")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Configure your new container settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let errorMessage {
                    Button {
                        showErrorPopover.toggle()
                    } label: {
                        Label(
                            "Error",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Show error")
                    .popover(isPresented: $showErrorPopover, arrowEdge: .bottom)
                    {
                        errorPopover(message: errorMessage)
                    }
                }
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 20) {
                            EditableField(
                                title: "Image",
                                placeholder: "alpine:latest",
                                value: $imageReference,
                                fieldWidth: Self.fieldWidth,
                                actionLabel: {
                                    Image(systemName: "ellipsis.circle")
                                },
                                action: {
                                    Task {
                                        do {
                                            self.showProgressView = true
                                            self.localImages =
                                                try await imageManager.list()
                                                .map(\.description)
                                            self.showProgressView = false
                                            self.showPickLocalImage = true
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }
                            )

                            EditableField(
                                title: "Name",
                                description:
                                    "Leave empty to generate a unique name automatically.",
                                placeholder: "my-container",
                                value: $container.name,
                                fieldWidth: Self.fieldWidth
                            )
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    processOptions
                    managementOptions
                }
                .padding(20)
            }

            Divider()

            // Bottom Bar
            HStack {
                if showProgressView {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Creating container...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !containerManager.progressMessage.isEmpty {
                            Text(containerManager.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                Button("Cancel") {
                    close()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Create Container") {
                    createContainer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    imageReference.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 660, height: 560)
        .modal(
            isPresented: $showProgressView,
            content: {
                ProgressView()
            }
        )
        .modal(
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
        .modal(
            item: $volumePickerTarget,
            content: { target in
                VolumeSelectionView(
                    volumes: self.availableVolumes,
                    onVolumeSelect: { selectedName in
                        guard
                            let index = self.volumes.firstIndex(where: {
                                $0.id == target.id
                            })
                        else { return }
                        self.volumes[index].name = selectedName
                    }
                )
            }
        )
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
        .animation(.default, value: self.isProcessOptionsExpanded)
        .animation(.default, value: self.isManagementOptionsExpanded)
        .onChange(of: errorMessage) { _, newValue in
            showErrorPopover = newValue != nil
        }
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()
    }

    private func errorPopover(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                Text("Error")
                    .font(.headline)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack {
                Spacer()

                Button("Dismiss") {
                    showErrorPopover = false
                    errorMessage = nil
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private static var platformOptions: [String] {
        let current = Platform.current
        var options = [current.description]

        if current.architecture == "arm64" {
            options.append("linux/amd64")
        }

        return options
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
                    editorContent: { $keyValue in
                        KeyValueEditor(keyValue: $keyValue)
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
                    title: "Volume Mounts",
                    columnTitles: ["Volume", "Path"],
                    fieldWidth: Self.fieldWidth,
                    addLabel: "Add Volume Mount",
                    newItem: { VolumeConfiguration() },
                    rowSummary: volumeMountSummary,
                    rowValues: volumeMountValues,
                    editorContent: { $volume in
                        VolumeRow(
                            volumeName: $volume.name,
                            path: $volume.path,
                            showAvailableVolume: {
                                showAvailableVolumes(for: volume.id)
                            }
                        )
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
                    editorContent: { $capability in
                        CapabilityEditor(capability: $capability)
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
            isExpanded.wrappedValue.toggle()
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

    private func showAvailableVolumes(for id: VolumeConfiguration.ID) {
        guard !self.volumeInitialized else {
            self.volumePickerTarget = VolumePickerTarget(id: id)
            return
        }

        Task {
            do {
                self.showProgressView = true
                self.availableVolumes = try await volumeManager.list()
                self.showProgressView = false
                self.volumeInitialized = true
                self.volumePickerTarget = VolumePickerTarget(id: id)
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
                let mountOptions: [String] = []
                let existingVolumes = try await volumeManager.list()

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
                        self.errorMessage =
                            "Volume mount path must be an absolute container path."
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
                })

                self.process.environments = validEnvironments.map { kv in
                    "\(kv.key)=\(kv.value)"
                }

                // Make copies for actor boundary crossing
                let process = self.process
                let container = self.container
                let resource = self.resource
                let registryScheme = self.registryScheme

                try await containerManager.create(
                    imageReference: trimmedReference,
                    imagesDir: UserDefaults.applicationDataRoot
                        .appendingPathComponent("images"),
                    arguments: [],
                    process: process,
                    container: container,
                    resource: resource,
                    registryScheme: registryScheme
                )

                close()

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

private struct CapabilityEditor: View {
    @Binding var capability: CapabilityConfiguration

    var body: some View {
        EditableField(
            title: "Capability",
            description:
                "Use normalized CAP_* names, for example CAP_NET_ADMIN.",
            placeholder: "CAP_NET_ADMIN",
            value: $capability.name
        )
    }
}

private struct VolumeRow: View {
    @Binding var volumeName: String
    @Binding var path: String

    var showAvailableVolume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                Text("Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("/data", text: $path)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
