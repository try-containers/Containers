//
//  ContainersApp.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import AppKit
import ContainerSystem
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start with dock icon showing since dashboard opens on launch
        NSApp.setActivationPolicy(.regular)

        // Observe window close notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Check if this is the dashboard window by title
        if window.title == "Containers" {
            // Hide dock icon immediately when dashboard closes
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@main
struct ContainersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var containerManager = ContainerManager()
    @State private var imageManager = ImageManager()
    @State private var volumeManager = VolumeManager()
    @State private var systemManager = SystemManager()
    @State private var networkManager = NetworkManager()

    static let dashboardWindowId = "dashboard"
    static let settingsWindowId = "settings"
    static let containerDetailWindowId = "container-detail"
    static let imageDetailWindowId = "image-detail"
    static let volumeDetailWindowId = "volume-detail"

    var body: some Scene {
        Window(
            "Containers",
            id: Self.dashboardWindowId,
            content: {
                DashboardView()
                    .environment(containerManager)
                    .environment(imageManager)
                    .environment(volumeManager)
                    .environment(systemManager)
                    .environment(networkManager)
                    .onAppear {
                        // Show dock icon when dashboard appears
                        NSApp.setActivationPolicy(.regular)
                    }
            }
        )
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra(
            content: {
                MenuBarItem()
                    .environment(systemManager)
            },
            label: {
                Image(systemManager.isRunning ? "server.play" : "server.pause")
            }
        )
        .menuBarExtraStyle(.menu)

        Window("Settings", id: Self.settingsWindowId) {
            SettingsView()
                .environment(networkManager)
                .environment(systemManager)
        }
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .commands { PreferencesCommands() }

        WindowGroup(
            "Container Details",
            id: Self.containerDetailWindowId,
            for: String.self
        ) { $id in
            if let id {
                ContainerDetailWindow(containerID: id)
                    .environment(containerManager)
                    .environment(volumeManager)
            }
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

        WindowGroup(
            "Image Details",
            id: Self.imageDetailWindowId,
            for: String.self
        ) { $reference in
            if let reference {
                ImageDetailWindow(imageReference: reference)
                    .environment(imageManager)
                    .environment(containerManager)
            }
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

        WindowGroup(
            "Volume Details",
            id: Self.volumeDetailWindowId,
            for: String.self
        ) { $volumeID in
            if let volumeID {
                VolumeDetailWindow(volumeID: volumeID)
                    .environment(volumeManager)
            }
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

    }

    struct PreferencesCommands: Commands {
        @Environment(\.openWindow) private var openWindow
        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    openWindow(id: ContainersApp.settingsWindowId)
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
            }
        }
    }
}
