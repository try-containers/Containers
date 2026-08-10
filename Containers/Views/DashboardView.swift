//
//  DashboardView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import AppKit
import ContainerSystem
import ContainerizationOCI
import SwiftUI
import TipKit

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
            "cube.transparent.fill"
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
    @SwiftUI.State private var selectedTab: NavigationTab =
        NavigationTab(rawValue: UserDefaults.lastSelectedTab) ?? .images
    @SwiftUI.State private var refreshContainerNeeded: Bool = false

    // Local error state
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false

    // Sheet presentation state for creating new items
    @SwiftUI.State private var isFirstLaunch: Bool = false
    @SwiftUI.State private var showWhatsNew: Bool = false
    @SwiftUI.State private var showCreateContainerView: Bool = false
    @SwiftUI.State private var showCreateVolumeView: Bool = false
    @SwiftUI.State private var showCreateImageView: Bool = false

    // Refresh trigger (still needed for build image sheet dismiss)
    @SwiftUI.State private var refreshTrigger: Int = 0

    // Search state
    @SwiftUI.State private var searchText: String = ""

    // Running containers only toggle
    @SwiftUI.State private var runningContainersOnly: Bool = false

    // Resource usage state
    @SwiftUI.State private var resources = ResourcesViewModel()

    @SwiftUI.State private var toolbarController = DashboardToolbarController()
    @SwiftUI.State private var showAddFirstImageTip: Bool = false

    private let addFirstImageTip = AddFirstImageTip()

    private var isSystemRunning: Bool { system.status == .running }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .containers:
            ContainersView(
                searchText: $searchText,
                runningContainersOnly: $runningContainersOnly,
                refreshTrigger: refreshTrigger
            )
            .padding(.top)
        case .images:
            ImagesView(
                searchText: $searchText,
                refreshTrigger: refreshTrigger
            )
            .padding(.top)
        case .volumes:
            VolumesView(
                searchText: $searchText,
                refreshTrigger: refreshTrigger
            )
            .padding(.top)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .disabled(!isSystemRunning)
                .overlay {
                    if !isSystemRunning {
                        SystemStatusView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .onAppear {
                    if UserDefaults.shouldShowWhatsNew {
                        isFirstLaunch = UserDefaults.lastSeenVersion.isEmpty
                        showWhatsNew = true
                    }
                }
                .task {
                    guard !self.isSystemRunning else {
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
                .alert(
                    "Oops!",
                    isPresented: $showError,
                    actions: {
                        Button(
                            action: {
                                self.showError = false
                            },
                            label: {
                                Text("OK")
                            }
                        )
                    },
                    message: {
                        let message = String(
                            "\(self.error, default: "Unknown Error")"
                        )
                        Text(message)
                            .lineLimit(5)
                    }
                )
                .onChange(of: selectedTab) { _, newTab in
                    UserDefaults.lastSelectedTab = newTab.rawValue
                }
                .onChange(of: showWhatsNew) { _, isShowing in
                    if !isShowing && isFirstLaunch {
                        AddFirstImageTip.shouldShow = true
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
                    WhatsNewView(isFirstLaunch: isFirstLaunch) {
                        UserDefaults.markCurrentVersionSeen()
                        showWhatsNew = false
                    }
                }
                .sheet(
                    isPresented: $showCreateContainerView,
                    onDismiss: {
                        refreshTrigger += 1
                    },
                    content: {
                        CreateContainerView(imageReference: "")
                    }
                )
                .sheet(
                    isPresented: $showCreateVolumeView,
                    onDismiss: {
                        refreshTrigger += 1
                    },
                    content: {
                        CreateVolumeView()
                    }
                )
                .sheet(
                    isPresented: $showCreateImageView,
                    onDismiss: {
                        refreshTrigger += 1
                    },
                    content: {
                        CreateImageView()
                    }
                )

            statusBar
        }
        // The floor the toolbar needs to keep every item out of the overflow
        // menu: below ~540 the buttons go first and the tabs follow at ~470.
        // The search field collapsing to a magnifier is the one thing meant to
        // happen on the way down, and it starts at ~620.
        .frame(minWidth: 560, minHeight: 320)
        .background(
            DashboardToolbarBinder(
                controller: toolbarController,
                tabs: NavigationTab.allCases.map(\.displayTitle),
                selectedIndex: NavigationTab.allCases
                    .firstIndex(of: selectedTab) ?? 0,
                isEnabled: isSystemRunning,
                showsFilter: selectedTab == .containers,
                isFilterOn: runningContainersOnly,
                searchText: searchText,
                onSelectTab: { index in
                    let all = NavigationTab.allCases
                    guard all.indices.contains(index) else { return }
                    selectedTab = all[index]
                },
                onToggleFilter: { runningContainersOnly = $0 },
                onAdd: {
                    addFirstImageTip.invalidate(reason: .actionPerformed)
                    handlePlusButton()
                },
                onSearch: { searchText = $0 },
                addTip: showAddFirstImageTip
                    ? AnyView(TipView(addFirstImageTip)) : nil
            )
        )
        .task {
            // The toolbar item is AppKit's, so nothing can carry `.popoverTip`
            // for it. Watching the tip here is what stands in for that.
            for await shouldDisplay in addFirstImageTip.shouldDisplayUpdates {
                showAddFirstImageTip = shouldDisplay
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Status message
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Control buttons (play/stop/restart)
            HStack(spacing: 8) {
                Button(
                    action: {
                        Task {
                            do {
                                if isSystemRunning {
                                    try await system.stop()
                                } else {
                                    try await startSystem()
                                }
                            } catch (let error) {
                                await MainActor.run {
                                    self.error = error
                                    self.showError = true
                                }
                            }
                        }
                    },
                    label: {
                        Image(
                            systemName: isSystemRunning
                                ? "stop.fill" : "play.fill"
                        )
                        .font(.caption)
                    }
                )
                .buttonStyle(.plain)
                .disabled(
                    system.status == .starting || system.status == .stopping
                )

                // Restart button (only visible when running)
                if system.status == .running {
                    Button(
                        action: {
                            Task {
                                do {
                                    try await system.stop()
                                    try await startSystem()
                                } catch (let error) {
                                    await MainActor.run {
                                        self.error = error
                                        self.showError = true
                                    }
                                }
                            }
                        },
                        label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(
                        system.status == .starting || system.status == .stopping
                    )
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
        switch system.status {
        case .running:
            return Color(nsColor: .systemGreen)
        case .starting, .stopping:
            return Color(nsColor: .systemOrange)
        case .notStarted, .failed:
            return Color(nsColor: .systemRed)
        }
    }

    private var statusMessage: String {
        switch system.status {
        case .running:
            return "System is running"
        case .starting:
            return "Starting system..."
        case .stopping:
            return "Stopping system..."
        case .notStarted:
            return "System is not started"
        case .failed:
            return "System failed to start"
        }
    }

    private func handlePlusButton() {
        guard system.status == .running else { return }

        switch selectedTab {
        case .containers:
            showCreateContainerView = true
        case .volumes:
            showCreateVolumeView = true
        case .images:
            showCreateImageView = true
        }
    }

    private func updateResourceUsage() async {
        guard system.status == .running else {
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
            memoryUsage: Double(runningContainers.count) * 0.128,  // For now, estimate ~128MB per running container
            cpuUsage: Double(runningContainers.count) * 5.0,  // 5% per container estimate
            diskUsage: Double(runningContainers.count) * 2.5,  // 2.5GB per container estimate
            diskLimit: 50,
        )
    }
}
