//
//  ContainersApp.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import AppKit
import ContainerSystem
import SwiftUI
import TipKit

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

    init() {
        do {
            try Tips.configure()
        } catch {
            print("TipKit configuration error: \(error)")
        }
    }

    @State private var containerManager = ContainerManager()
    @State private var imageManager = ImageManager()
    @State private var volumeManager = VolumeManager()
    @State private var systemManager = SystemManager()
    @State private var networkManager = NetworkManager()

    static let dashboardWindowID = "dashboard"
    static let settingsWindowID = "settings"
    static let containerDetailWindowID = "container-detail"
    static let imageDetailWindowID = "image-detail"
    static let volumeDetailWindowID = "volume-detail"

    var body: some Scene {
        Window(
            "Containers",
            id: Self.dashboardWindowID,
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
                Image(systemManager.status == .running ? "server.play" : "server.pause")
            }
        )
        .menuBarExtraStyle(.menu)

        Window("Settings", id: Self.settingsWindowID) {
            SettingsView()
                .environment(networkManager)
                .environment(systemManager)
        }
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .commands { PreferencesCommands() }

        windowGroup(
            "Container Details",
            id: Self.containerDetailWindowID,
            placeholder: DetailPlaceholder.container
        ) { id in
            ContainerDetailWindow(id: id)
                .environment(containerManager)
                .environment(volumeManager)
                .environment(imageManager)
        }

        windowGroup(
            "Image Details",
            id: Self.imageDetailWindowID,
            placeholder: DetailPlaceholder.image
        ) { reference in
            ImageDetailWindow(imageReference: reference)
                .environment(imageManager)
                .environment(containerManager)
                .environment(volumeManager)
        }

        windowGroup(
            "Volume Details",
            id: Self.volumeDetailWindowID,
            placeholder: DetailPlaceholder.volume
        ) { volumeID in
            VolumeDetailWindow(id: volumeID)
                .environment(volumeManager)
        }
    }

    /// A detail window group, keyed by the id of what it shows.
    private func windowGroup<Content: View>(
        _ title: String,
        id: String,
        placeholder: CGSize,
        @ViewBuilder content: @escaping (String) -> Content
    ) -> some Scene {
        WindowGroup(title, id: id, for: String.self) { $value in
            if let value {
                content(value)
            }
        }
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { _, context in
            DetailPlaceholder.centred(
                on: context.defaultDisplay.visibleRect,
                size: placeholder
            )
        }
        .commandsRemoved()
    }

    struct PreferencesCommands: Commands {
        @Environment(\.openWindow) private var openWindow
        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    openWindow(id: ContainersApp.settingsWindowID)
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
            }
        }
    }
}
