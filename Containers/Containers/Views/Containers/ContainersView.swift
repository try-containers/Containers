//
//  ContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import ContainerSystem
import ContainerResource

struct ContainersView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(SystemManager.self) private var system

    @Binding var searchText: String
    @Binding var runningContainerOnly: Bool
    @Binding var selectedContainerID: String?

    @SwiftUI.State private var containers: [ContainerViewModel] = []
    @SwiftUI.State private var lastUpdated: Date? = nil
    @SwiftUI.State private var selections = Set<ContainerViewModel.ID>()
    @SwiftUI.State private var showCreateContainerView: Bool = false
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    
    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredContainers: [ContainerViewModel] {
        if trimmedText.isEmpty {
            return runningContainerOnly ? containers.filter({$0.status == .running}): containers
        }
        let filtered = self.containers.filter({
            $0.name.contains(trimmedText) == true ||
            $0.imageName.contains(trimmedText) ||
            $0.formattedPorts.contains(trimmedText) == true ||
            $0.formattedIPAddress.contains(trimmedText) == true
        })
        
        return runningContainerOnly ? filtered.filter({$0.status == .running}): filtered
    }
    
    var body: some View {
        VStack(alignment: .leading , spacing: 0) {
            Table(
                of: ContainerViewModel.self,
                selection: $selections,
                columns: {
                    TableColumn("Name") { container in
                        
                        Button(action: {
                            selectedContainerID = container.id
                        }, label: {
                            Text(container.name)
                                .font(.headline)
                                .lineLimit(1)
                                .underline()
                            
                        })
                        .buttonStyle(.link)
                        .frame(height: 48) // to set minimum row height
                    }
                    .width(min: 100, ideal: 150, max: 250)
                    
                    TableColumn("Image") { container in
                        Text(container.imageName)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180, max: 300)

                    TableColumn("OS") { container in
                        Text(container.formattedOS)
                    }
                    .width(min: 36, ideal: 36, max: 72)

                    TableColumn("Arch") { container in
                        Text(container.formattedArch)
                    }
                    .width(min: 48, ideal: 48, max: 72)

                    TableColumn("State") { container in
                        Text(container.formattedState)
                    }
                    .width(min: 64, ideal: 80, max: 100)

                    TableColumn("IP Address") { container in
                        Text(container.formattedIPAddress)
                            .lineLimit(1)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(!container.hasIPAddress ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    .width(min: 100, ideal: 120, max: 140)

                    TableColumn("CPUs") { container in
                        Text(container.formattedCPUs)
                            .lineLimit(1)
                    }
                    .width(min: 36, ideal: 48, max: 64)

                    TableColumn("Memory") { container in
                        Text(container.formattedMemory)
                            .lineLimit(1)
                    }
                    .width(min: 56, ideal: 72, max: 96)
                    
                    TableColumn("Actions") { container in
                        
                        HStack(spacing: 12) {
                            switch container.status {
                            case .running:
                                Button(
                                    action: {
                                        Task {
                                            do {
                                                try await containerManager.stop(
                                                    snapshots: [container.snapshot],
                                                    timeoutSeconds: Int32(UserDefaults.stopContainerTimeoutSeconds)
                                                )
                                                
                                                do {
                                                    self.containers = (try await containerManager.list()).map({ContainerViewModel($0)})
                                                    self.lastUpdated = Date()
                                                } catch(let err) {
                                                    self.error = err
                                                    self.showError = true
                                                }
                                            } catch (let err) {
                                                self.error = err
                                                self.showError = true
                                            }
                                        }
                                    },
                                    label: {
                                        Image(systemName: "stop.fill")
                                            .foregroundStyle(.gray)
                                    })
                                .buttonStyle(.plain)
                                
                            case .stopped:
                                Button(action: {
                                    Task {
                                        do {
                                            try await containerManager.start(id: container.snapshot.configuration.id, attachStdout: false, attachStdin: false)

                                            do {
                                                self.containers = (try await containerManager.list()).map({
                                                    ContainerViewModel($0)
                                                })
                                                self.lastUpdated = Date()
                                            } catch(let err) {
                                                self.error = err
                                                self.showError = true
                                            }
                                        } catch (let err) {
                                            self.error = err
                                            self.showError = true
                                        }
                                    }
                                }, label: {
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.blue)
                                })
                                .buttonStyle(.plain)
                                
                            case .stopping:
                                Image(systemName: "slash.circle")
                                    .foregroundStyle(.secondary)
                                
                            case .unknown:
                                Image(systemName: "slash.circle")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                                .padding(.vertical, 12)
                            
                            Button(action: {
                                Task {
                                    do {
                                        try await containerManager.delete(snapshots: [container.snapshot], force: true)
                                    } catch (let err) {
                                        self.error = err
                                        self.showError = true
                                    }
                                }
                                
                            }, label: {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.red)
                            })
                            .buttonStyle(.plain)
                            
                        }
                        .padding(.horizontal, 8)

                    }
                    .width(min: 92, ideal: 92, max: 92)
                },
                rows: {
                    ForEach(filteredContainers)
                })
            .tableStyle(.automatic)
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.system.isRunning {
                    ContainerSystemView()
                } else if filteredContainers.isEmpty {
                    ContentUnavailableView(
                        self.trimmedText.isEmpty && !self.runningContainerOnly ? "No Containers Found" : "No Matching Containers",
                        systemImage: NavigationTab.container.icon
                    )
                }
            })
        }
        .onChange(of: self.system.isRunning, initial: true, {
            guard self.system.isRunning else {
                self.containers = []
                self.lastUpdated = nil
                return
            }

            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                
                do {
                    self.containers = (try await containerManager.list()).map({ContainerViewModel($0)})
                    self.lastUpdated = Date()
                } catch(let err) {
                    self.error = err
                    self.showError = true
                }
            }
        })
        .sheet(isPresented: $showCreateContainerView, onDismiss: {
            Task {
                do {
                    self.containers = (try await containerManager.list()).map({ContainerViewModel($0)})
                    self.lastUpdated = Date()
                } catch(let err) {
                    self.error = err
                    self.showError = true
                }
            }
        }, content: {
            CreateContainerView(imageReference: "")
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
}

//#Preview {
//    ContainerListView()
//        .environment(ApplicationManager())
//        .environment(UserSettingsManager())
//}
