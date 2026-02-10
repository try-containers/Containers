//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import ContainerSystem
import ContainerizationOCI
import ContainerResource
import ContainerAPIClient
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
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var volumeInitialized: Bool = false
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var showAdditionalSettings: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var showPickVolume: Bool = false
    
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
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Image")
                                    .font(.headline)
                                Spacer()
                                Text("Local or Remote")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 8) {
                                TextField("alpine:latest", text: $imageReference)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(action: {
                                    Task {
                                        do {
                                            self.showProgressView = true
                                            self.localImages = try await imageManager.list()
                                            self.showProgressView = false
                                            self.showPickLocalImage = true
                                        } catch (let error) {
                                            self.errorMessage = "\(error)"
                                        }
                                    }
                                }, label: {
                                    Image(systemName: "ellipsis.circle")
                                })
                                .buttonStyle(.plain)
                                .help("Choose from local images")
                            }
                        }
                        .padding(12)
                    }
                    
                    // Optional Settings Disclosure
                    DisclosureGroup(
                        isExpanded: $showAdditionalSettings,
                        content: {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                additionalSettings
                            }
                            .padding(.top, 12)
                        },
                        label: {
                            Label {
                                Text("Optional Settings")
                                    .font(.headline)
                            } icon: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    Text("Creating container...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showProgressView, content: {
            ProgressView()
        })
        .sheet(isPresented: $showPickLocalImage, content: {
            ImageSelectionView(images: self.localImages, onImageSelect: {
                self.imageReference = $0
            })
        })
        .animation(.default, value: self.ports.count)
        .animation(.default, value: self.environments.count)
        .onDisappear {
            self.showProgressView = false
        }
        .interactiveDismissDisabled()
    }
    
    func createContainer() {
        
        let trimmedReference = imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedReference.isEmpty else {
            self.errorMessage = "Image is not specified."
            return
        }
        
        Task {
            //self.showProgressView = true
            
            do {
                var validVolumeFSs: [Filesystem] = []
                let mountOptions: [String] = []
                
                for volumeConfig in self.volumes {
                    var volume: Volume
                    
                    if let first = self.availableVolumes.first(where: {$0.name == volumeConfig.name}) {
                        volume = first
                    } else {
                        var trimmedName = volumeConfig.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        var labels: [KeyValue] = []

                        if trimmedName.isEmpty {
                            trimmedName = VolumeStorage.generateAnonymousVolumeName()
                            labels.append(.init(key: Volume.anonymousLabel))
                        }

                        let vol = try await volumeManager.create(name: trimmedName, labels: labels, options: [], sizeInBytes: nil)
                        
                        volume = vol
                    }
                    
                    let fs = Filesystem.volume(name: volume.name, format: volume.format, source: volume.source, destination: volumeConfig.path, options: mountOptions)
                    
                    validVolumeFSs.append(fs)
                }
                
                self.container.volumes = validVolumeFSs
                
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
            
            //self.showProgressView = false
        }
    }
    
    @ViewBuilder
    private var additionalSettings: some View {
        VStack(spacing: 16) {
            // Container Name
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Container Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("If empty, a generated UUID will be used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Auto-generated", text: $container.name)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Entrypoint
            GroupBox {
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
            
            // Ports
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Port Mappings")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("[Host-ip:]Host:Container")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Ports set to 0 will be ignored. Host-ip defaults to 127.0.0.1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if ports.isEmpty {
                        Button {
                            self.ports.append(.init())
                        } label: {
                            Label("Add Port Mapping", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        ForEach($ports) { $port in
                            EditableRow(content: {
                                TextField("127.0.0.1", text: $port.hostAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 100)
                                Text(":")
                                TextField("8080", value: $port.host, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                Text(":")
                                TextField("80", value: $port.container, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                Picker("", selection: $port.publishProtocol) {
                                    Text("TCP").tag(PublishProtocol.tcp)
                                    Text("UDP").tag(PublishProtocol.udp)
                                }
                                .labelsHidden()
                                .fixedSize()
                            }, onAdd: {
                                self.ports.append(.init())
                            }, onDelete: {
                                self.ports.removeAll(where: {$0.id == port.id})
                            })
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            // Environment Variables
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    KeyValuesEditView(keyValues: $environments, title: "Environment Variables")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            
            /*/ Volumes
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Volume Mounts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("<name>:/path")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("If volume name is empty or not found, a new volume will be created")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if self.volumes.isEmpty {
                        Button {
                            self.volumes.append(.init())
                        } label: {
                            Label("Add Volume Mount", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        ForEach($volumes) { $volume in
                            EditableRow(content: {
                                VolumeRow(
                                    volumeName: $volume.name,
                                    path: $volume.path,
                                    showPickVolume: $showPickVolume,
                                    availableVolumes: $availableVolumes,
                                    showAvailableVolume: {
                                        guard !self.volumeInitialized else {
                                            self.showPickVolume = true
                                            return
                                        }

                                        Task {
                                            do {
                                                self.showProgressView = true
                                                self.availableVolumes = try await volumeManager.list()
                                                self.showProgressView = false
                                                self.volumeInitialized = true
                                                self.showPickVolume = true
                                            } catch (let error) {
                                                self.errorMessage = "\(error)"
                                            }
                                        }
                                    })
                            }, onAdd: {
                                self.volumes.append(.init())
                            }, onDelete: {
                                self.volumes.removeAll(where: {$0.id == volume.id})
                            })
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }*/
        }
    }
}

private struct VolumeRow: View {
    @Binding var volumeName: String
    @Binding var path: String
    @Binding var showPickVolume: Bool
    @Binding var availableVolumes: [Volume]
    
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
                        Image(systemName: "ellipsis.circle")
                    })
                    .buttonStyle(.plain)
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
        .sheet(isPresented: $showPickVolume, content: {
            VolumeSelectionView(volumes: self.availableVolumes, onVolumeSelect: {
                self.volumeName = $0
            })
        })
    }
}
