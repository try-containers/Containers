//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import ContainerSystem
import ContainerizationOCI
import ContainerizationExtras

private struct PortsConfiguration: Identifiable {
    let id: UUID = UUID()
    var hostAddress: String = "127.0.0.1"
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp
    
    var publishedPort: PublishPort {
        let address = try? IPAddress(hostAddress.trimmingCharacters(in: .whitespacesAndNewlines))
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

private struct ContainerPlatformOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct CreateContainerView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(ContainerManager.self) private var containerManager
    @Environment(\.dismiss) private var dismiss
    
    @SwiftUI.State var imageReference: String
    
    @SwiftUI.State private var process: ContainerProcess = .init()
    @SwiftUI.State private var container: ContainerInfo = .init()
    @SwiftUI.State private var volumes: [VolumeConfiguration] = []
    @SwiftUI.State private var ports: [PortsConfiguration] = []
    @SwiftUI.State private var environments: [KeyValue] = []
    @SwiftUI.State private var resource: ContainerConfiguration.Resources = .init()
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto.rawValue
    @SwiftUI.State private var platformString: String = Platform.current.description
    @SwiftUI.State private var shmSizeInMiB: Int = 0
    @SwiftUI.State private var capAddText: String = ""
    @SwiftUI.State private var capDropText: String = ""
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var volumeInitialized: Bool = false
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var showAdditionalSettings: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var volumePickerTarget: VolumePickerTarget?
    
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
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Error message
                    if let errorMessage = self.errorMessage {
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
                    
                    // Image Section
                    
                    EditableField(
                        title: "Image",
                        placeholder: "alpine:latest",
                        value: $imageReference,
                        actionLabel: {
                            Image(systemName: "ellipsis.circle")
                        },
                        action: {
                            Task {
                                do {
                                    self.showProgressView = true
                                    self.localImages = try await imageManager.list().map(\.description)
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
                        description: "Leave empty to generate a unique name automatically.",
                        placeholder: "my-container",
                        value: $container.name
                    )

                    EditableList(
                        items: $volumes,
                        title: "Volume Mounts",
                        addLabel: "Add Volume Mount",
                        newItem: { VolumeConfiguration() },
                        rowSummary: volumeMountSummary,
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
                    
                    // Optional Settings Disclosure
                    DisclosureGroup(
                        isExpanded: $showAdditionalSettings,
                        content: {
                            VStack(alignment: .leading, spacing: 16) {
                                additionalSettings
                            }
                            .padding(.top, 12)
                        },
                        label: {
                         
                                Text("Optional Settings")
                                    .font(.headline)
                           
                        }
                    )
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
                    self.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Create Container") {
                    createContainer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(imageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 450, height: 500)
        .sheet(isPresented: $showProgressView, content: {
            ProgressView()
        })
        .sheet(isPresented: $showPickLocalImage, content: {
            ImageSelectionView(images: self.localImages, onImageSelect: {
                self.imageReference = $0
            })
        })
        .sheet(item: $volumePickerTarget, content: { target in
            VolumeSelectionView(volumes: self.availableVolumes, onVolumeSelect: { selectedName in
                guard let index = self.volumes.firstIndex(where: { $0.id == target.id }) else { return }
                self.volumes[index].name = selectedName
            })
        })
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()
    }
    
    private static var platformOptions: [ContainerPlatformOption] {
        let current = Platform.current
        var options: [ContainerPlatformOption] = [
            ContainerPlatformOption(
                id: current.description,
                title: "Linux \(current.architecture.uppercased())",
                detail: "Default platform"
            )
        ]
        
        if current.architecture == "arm64" {
            options.append(
                ContainerPlatformOption(
                    id: "linux/amd64",
                    title: "Linux AMD64",
                    detail: "Run with Rosetta"
                )
            )
        }
        
        return options
    }
    
    private func createContainer() {
        let trimmedReference = imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
                    let trimmedName = volumeConfig.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let destination = volumeConfig.path.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasMountInput = !trimmedName.isEmpty || !destination.isEmpty
                    
                    guard hasMountInput else {
                        continue
                    }
                    
                    guard destination.hasPrefix("/") else {
                        self.errorMessage = "Volume mount path must be an absolute container path."
                        return
                    }
                    
                    let volume: Volume
                    if let existingVolume = existingVolumes.first(where: { $0.name == trimmedName }) {
                        volume = existingVolume
                    } else {
                        var volumeName = trimmedName
                        var labels: [KeyValue] = []
                        
                        if volumeName.isEmpty {
                            volumeName = VolumeStorage.generateAnonymousVolumeName()
                            labels.append(.init(key: Volume.anonymousLabel))
                        }
                        
                        volume = try await volumeManager.create(name: volumeName, labels: labels, options: [], sizeInBytes: nil)
                    }
                    
                    let fs = Filesystem.volume(name: volume.name, format: volume.format, source: volume.source, destination: destination, options: mountOptions)
                    
                    validVolumeFSs.append(fs)
                }
                
                self.container.volumes = validVolumeFSs
                self.container.platform = self.platformString
                self.container.shmSize = self.shmSizeInMiB > 0 ? UInt64(self.shmSizeInMiB) * 1024 * 1024 : nil
                self.container.capAdd = Self.commaSeparatedValues(from: self.capAddText)
                self.container.capDrop = Self.commaSeparatedValues(from: self.capDropText)
                
                let validPorts = self.ports.filter({$0.host > 0 && $0.container > 0})
                
                self.container.publishPorts = validPorts.map(\.publishedPort)
                
                let validEnvironments = self.environments.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})
                
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
                    imagesDir: UserDefaults.applicationDataRoot.appendingPathComponent("images"),
                    arguments: [],
                    process: process,
                    container: container,
                    resource: resource,
                    registryScheme: registryScheme
                )
                
                self.dismiss()
                
            } catch (let error) {
                self.errorMessage = "\(error)"
            }
            
            self.showProgressView = false
        }
    }
    
    @ViewBuilder
    private var additionalSettings: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Platform", selection: $platformString) {
                        ForEach(Self.platformOptions) { option in
                            VStack(alignment: .leading) {
                                Text(option.title)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Entrypoint
            GroupBox  {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entrypoint")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Overrides the image's default entrypoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("/bin/sh -c \"echo hello\"", text: Binding(
                        get: { container.entryPoint ?? "" },
                        set: { container.entryPoint = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Runtime
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Runtime")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Runtime Handler", text: $container.runtimeHandler)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    TextField("Stop Signal", text: Binding(
                        get: { container.stopSignal ?? "" },
                        set: { container.stopSignal = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    
                    TextField("Shared Memory (MiB)", value: $shmSizeInMiB, format: .number)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle("Read-only root filesystem", isOn: $container.readOnly)
                    Toggle("Use init process", isOn: $container.useInit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Capabilities
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Linux Capabilities")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Separate multiple capabilities with commas. Use normalized CAP_* names or ALL.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Add capabilities", text: $capAddText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    TextField("Drop capabilities", text: $capDropText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Ports
            
            EditableList(
                items: $ports,
                title: "Port Mappings",
                addLabel: "Add Port Mapping",
                newItem: { PortsConfiguration() },
                rowSummary: portSummary,
                editorContent: { $port in
                    PortMappingEditor(port: $port)
                }
            )

            // Environment Variables
            
            
            EditableList(
                items: $environments,
                title: "Environment Variables",
                addLabel: "Add Environment Variable",
                newItem: { KeyValue() },
                rowSummary: keyValueSummary,
                editorContent: { $keyValue in
                    KeyValueEditor(keyValue: $keyValue)
                }
            )
        }
    }
    
    private static func commaSeparatedValues(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func volumeMountSummary(_ volume: VolumeConfiguration) -> String {
        let name = volume.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = volume.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "Anonymous volume" : name
        return path.isEmpty ? displayName : "\(displayName) -> \(path)"
    }
    
    private func portSummary(_ port: PortsConfiguration) -> String {
        "\(port.hostAddress):\(port.host):\(port.container)/\(port.publishProtocol.rawValue.uppercased())"
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
                TextField("Container Port", value: $port.container, format: .number)
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
                    Button(action: {
                        self.showAvailableVolume()
                    }, label: {
                        Label("Choose", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    })
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
