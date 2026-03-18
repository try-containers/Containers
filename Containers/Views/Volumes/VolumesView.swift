//
//  VolumeListView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import ContainerSystem


struct VolumesView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(SystemManager.self) private var system

    @Binding var searchText: String
    var refreshTrigger: Int

    @State private var volumes: [VolumeViewModel] = []
    @State private var lastUpdated: Date? = nil
    @State private var selections = Set<VolumeViewModel.ID>()
    @State private var showLabelForVolume: VolumeViewModel?
    @State private var showOptionForVolume: VolumeViewModel?
    @State private var showInUseContainerForVolume: VolumeViewModel?
    @State private var showCreateVolumeView: Bool = false
    @State private var error: Error?
    @State private var showError: Bool = false

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredVolumes: [VolumeViewModel] {
        if trimmedText.isEmpty {
            return volumes
        }
        let filtered = self.volumes.filter({
            $0.name.contains(trimmedText)
        })
        
        return filtered
    }

    var body: some View {
        VStack(alignment: .leading , spacing: 0) {
            Table(of: VolumeViewModel.self, selection: $selections, columns: {
                
                TableColumn("Name") { volume in
                    Text(volume.name)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(height: 48)
                }
                .width(min: 80, ideal: 80)
                
                TableColumn("Type") { volume in
                    Text(volume.volumeType.rawValue)
                }
                .width(80)

                TableColumn("State") { volume in
                    Group {
                        if volume.inUse {
                            Button(action: {
                                showInUseContainerForVolume = volume
                            }, label: {
                                Text("In use")
                                    .lineLimit(1)
                                    .underline()

                            })
                            .buttonStyle(.link)
                        } else {
                            Text("Unused")
                        }
                    }
                    .lineLimit(1)

                }
                .width(64)

                TableColumn("Size") { volume in
                    if let size = volume.formattedSize {
                        Text(size)
                    } else {
                        Text("(Not Specified")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 80, ideal: 80, max: 120)

                
                TableColumn("Created") { volume in
                    Text(volume.formattedCreated)
                }
                .width(min: 80, ideal: 80, max: 160)
                
                
                TableColumn("Driver") { volume in
                    Text(volume.driver)
                        .lineLimit(1)
                }
                .width(64)

                
                TableColumn("Format") { volume in
                    Text(volume.format)
                        .lineLimit(1)
                }
                .width(64)

                TableColumn("Source") { volume in
                    let source = volume.source
                    let fileURL = URL(filePath: source)
                    HStack(spacing: 8) {
                        Text(source)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200)
                    
                        Button {
                            self.openFile(fileURL)
                        } label: {
                            Image(systemName: "arrow.right")
                                .contentShape(Rectangle())
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.link)
                    }

                }
                .width(min: 160, ideal: 160, max: 240)
                                
                TableColumn("Label & Option") { volume in
                    let labels = volume.labels
                    let options = volume.options
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            self.showLabelForVolume = volume
                        }, label: {
                            Text("- Labels")
                        })
                        .disabled(labels.isEmpty)
                        Button(action: {
                            self.showOptionForVolume = volume
                        }, label: {
                            Text("- Options")
                        })
                        .disabled(options.isEmpty)
                    }
                    .buttonStyle(.link)
                }
                .width(120)

                TableColumn("Actions") { volume in

                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                do {
                                    try await volumeManager.delete(volumes: [volume.volume])

                                    await self.listVolumes()
                                } catch (let err) {
                                    self.error = err
                                    self.showError = true
                                }
                            }
                        }, label: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(volume.inUse ? .secondary : Color.red)
                        })
                        .disabled(volume.inUse)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                }
                .width(80)
                
            }, rows: {
                ForEach(filteredVolumes)
            })
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.system.isRunning {
                    ContainerSystemView()
                } else if filteredVolumes.isEmpty {
                    ContentUnavailableView(
                        trimmedText.isEmpty ? "No Volumes Found" : "No Matching Volumes",
                        systemImage: NavigationTab.volumes.icon
                    )
                }
            })
        }
        .onChange(of: self.system.isRunning, initial: true, {
            guard self.system.isRunning else {
                self.volumes = []
                self.lastUpdated = nil
                return
            }
            
            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                await self.listVolumes()
            }
        })
        .onChange(of: refreshTrigger) {
            Task {
                await self.listVolumes()
            }
        }
        .onAppear {
            Task {
                guard system.isRunning else { return }
                await self.listVolumes()
            }
        }
        .sheet(isPresented: $showCreateVolumeView, onDismiss: {
            Task {
                await self.listVolumes()
            }
        }, content: {
            CreateVolumeView()
        })
        .sheet(item: $showInUseContainerForVolume, content: { volume in
            ImageContainersView(containers: volume.inUseContainers.map({ContainerViewModel($0)}))
        })
        .sheet(item: $showLabelForVolume, content: { volume in
            VolumeDetailOptionView(dictionary: volume.labels, title: "Metadata", emptyText: "No Metadata Specified.")
        })
        .sheet(item: $showOptionForVolume, content: { volume in
            VolumeDetailOptionView(dictionary: volume.options, title: "Driver Specific Options", emptyText: "No Options Specified.")
        })
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        })
    }

    func listVolumes() async {
        do {
            let containers = try await containerManager.list()
            let volumes = try await volumeManager.list()
            let displayModels: [VolumeViewModel] = volumes
                .map({VolumeViewModel($0, containers: containers)})
                .sorted { $0.name < $1.name }

            self.volumes = displayModels
            self.lastUpdated = Date()

        } catch(let err) {
            self.error = err
            self.showError = true
        }
    }

    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absoluteString,
            inFileViewerRootedAtPath: url.parent.absoluteString
        )
    }
}

private struct VolumeDetailOptionView: View {
    var dictionary: [String : String]
    var title: String
    var emptyText: String

    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let keyValueModels = KeyValue.from(dictionary: dictionary)
        
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Key=Value")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            KeyValuesView(keyValues: keyValueModels, emptyText: emptyText, leftColumnWidth: 120)
            
        }
        .padding(.all, 24)
        .frame(width: 320, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .topTrailing, content: {
            Button(action: {
                self.dismiss()
            }, label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            })
            .buttonStyle(.plain)
            .padding(.all, 24)
        })
        .interactiveDismissDisabled(false)

    }
        
}
