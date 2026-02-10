//
//  DashboardView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import AppKit
import ContainerSystem
import ContainerizationOCI
import ContainerResource

enum NavigationTab: String, Identifiable, Equatable {
    case containers
    case images
    case volumes
    
    var displayTitle: String {
        switch self {
        case .containers:
            "Containers"
        case .images:
            "Images"
        case .volumes:
            "Volumes"
        }
    }
    
    var icon: String {
        switch self {
        case .containers:
            "cube.fill"
        case .images:
            "cloud.fill"
        case .volumes:
            "internaldrive.fill"
        }
    }
    
    var id: String {
        self.rawValue
    }
    
    // for customizing order
    static let allCases: [NavigationTab] = [.containers, .images, .volumes]
}

struct DashboardView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(SystemManager.self) private var system
    @Environment(\.openSettings) private var openSettings
    
    // Local navigation state
    @SwiftUI.State private var selectedTab: NavigationTab = .containers
    @SwiftUI.State private var refreshContainerNeeded: Bool = false
    
    // Local error state
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    
    // Sheet presentation state for creating new items
    @SwiftUI.State private var showCreateContainerView: Bool = false
    @SwiftUI.State private var showCreateVolumeView: Bool = false
    @SwiftUI.State private var showBuildImageView: Bool = false
    
    // Refresh trigger
    @SwiftUI.State private var refreshTrigger: Int = 0
    
    // Search state
    @SwiftUI.State private var searchText: String = ""
    
    // Running containers only toggle
    @SwiftUI.State private var runningContainersOnly: Bool = false
    
    // Resource usage state
    @SwiftUI.State private var resources = ResourcesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                ForEach(NavigationTab.allCases) { tab in
                    NavigationStack {
                        switch tab {
                        case .containers:
                            ContainersView(
                                searchText: $searchText,
                                runningContainersOnly: $runningContainersOnly
                            )
                            .id("containers-\(refreshTrigger)")
                            .padding(.vertical)
                        case .images:
                            ImagesView(searchText: $searchText)
                                .id("images-\(refreshTrigger)")
                                .padding(.vertical)
                        case .volumes:
                            VolumesView(searchText: $searchText)
                                .id("volumes-\(refreshTrigger)")
                                .padding(.vertical)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .toolbarBackground(.hidden, for: .automatic)
                    .tabItem {
                        Label(tab.displayTitle, systemImage: tab.icon)
                    }
                    .tag(tab)
                }
            }
            .tabViewStyle(.automatic)
            .toolbar {
                if selectedTab == .containers {
                    ToolbarItem(placement: .automatic) {
                        Toggle(isOn: $runningContainersOnly, label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        })
                        .toggleStyle(.button)
                        .help("Running containers only")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        refreshTrigger += 1
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    .help("Refresh")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        handlePlusButton()
                    }, label: {
                        Image(systemName: "plus")
                    })
                    .disabled(selectedTab == .volumes)
                    .help("New")
                }
                
                ToolbarSpacer(.fixed)
                
                ToolbarItem(placement: .automatic) {
                    SearchField(text: $searchText)
                }
            }
            .task {
                guard !self.system.isRunning else {
                    return
                }
                
                try? await self.system.start(
                    appRoot: UserDefaults.applicationDataRoot
                )
            }
            .task {
                // Update resource usage every 2 seconds
                while !Task.isCancelled {
                    await updateResourceUsage()
                    
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .alert("Oops!", isPresented: $showError, actions: {
                Button(action: {
                    self.showError = false
                }, label: {
                    Text("OK")
                })
            }, message: {
                let message = String("\(self.error, default: "Unknown Error")")
                Text(message)
                    .lineLimit(5)
            })
            .sheet(isPresented: $showCreateContainerView, content: {
                CreateContainerView(imageReference: "")
            })
            .sheet(isPresented: $showCreateVolumeView, content: {
                CreateVolumeView()
            })
            .sheet(isPresented: $showBuildImageView, onDismiss: {
                refreshTrigger += 1
            }, content: {
                BuildImageView()
            })

            statusBar
        }
        .frame(minWidth: 800, minHeight: 520)
    }
    
    private var statusBar: some View {
        HStack(spacing: 16) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Status message
            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Control buttons (play/stop/restart)
            HStack(spacing: 8) {
                Button(action: {
                    Task { @MainActor in
                        if system.systemStatus == .running {
                            do {
                                try await system.stop()
                            } catch(let error) {
                                self.error = error
                                self.showError = true
                            }
                        } else {
                            do {
                                try await startSystem()
                            } catch(let error) {
                                self.error = error
                                self.showError = true
                            }
                        }
                    }
                }, label: {
                    Image(systemName: system.systemStatus == .running ? "stop.fill" : "play.fill")
                        .font(.caption)
                })
                .buttonStyle(.plain)
                .disabled(system.systemStatus == .starting || system.systemStatus == .stopping)
                
                // Restart button (only visible when running)
                if system.systemStatus == .running {
                    Button(action: {
                        Task { @MainActor in
                            do {
                                try await system.stop()
                                try await startSystem()
                            } catch(let error) {
                                self.error = error
                                self.showError = true
                            }
                        }
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    })
                    .buttonStyle(.plain)
                    .disabled(system.systemStatus == .starting || system.systemStatus == .stopping)
                }
            }
            
            // Separator
            Divider()
                .frame(height: 16)
            
            // Resource usage
            HStack(spacing: 12) {
                // RAM usage
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.caption)
                    Text(String(format: "%.2f GB", resources.memoryUsage))
                        .font(.caption)
                }
                
                // CPU usage
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption)
                    Text(String(format: "%.0f%%", resources.cpuUsage))
                        .font(.caption)
                }
                
                // Disk usage
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                    Text(String(format: "%.2f GB", resources.diskUsage))
                        .font(.caption)
                    Text(String(format: "(limit %.0f GB)", resources.diskLimit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
    
    private func startSystem() async throws {
        try await system.start(
            appRoot: UserDefaults.applicationDataRoot
        )
    }
    
    private var statusColor: Color {
        switch system.systemStatus {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .notStarted, .failed:
            return .red
        }
    }
    
    private var statusMessage: String {
        switch system.systemStatus {
        case .running:
            return "Container system is running"
        case .starting:
            return "Starting container system..."
        case .stopping:
            return "Stopping container system..."
        case .notStarted:
            return "Container system is not started"
        case .failed:
            return "Container system failed to start"
        }
    }
    
    private func handlePlusButton() {
        switch selectedTab {
        case .containers:
            showCreateContainerView = true
        case .volumes:
            showCreateVolumeView = true
        case .images:
            showBuildImageView = true
        }
    }
    
    private func updateResourceUsage() async {
        guard system.isRunning else {
            resources = ResourcesViewModel(
                memoryUsage: 0,
                cpuUsage: 0,
                diskUsage: 0,
                diskLimit: 0
            )
            
            return
        }
        
        // Get container list through ContainerManager
        guard let snapshots = try? await containerManager.list() else {
            return
        }
        
        let runningContainers = snapshots.filter { $0.status == .running }
        
        resources = ResourcesViewModel(
            memoryUsage:  Double(runningContainers.count) * 0.128, // For now, estimate ~128MB per running container
            cpuUsage:  Double(runningContainers.count) * 5.0, // 5% per container estimate
            diskUsage:  Double(runningContainers.count) * 2.5, // 2.5GB per container estimate
            diskLimit: 50,
        )
    }
}

