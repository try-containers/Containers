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
    static let dashboardWindowId = "dashboard"

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var containerManager = ContainerManager()
    @State private var imageManager = ImageManager()
    @State private var volumeManager = VolumeManager()
    @State private var builderManager = BuilderManager()
    @State private var systemManager = SystemManager()
    @State private var dnsManager = DNSManager()
    
    var body: some Scene {
        
        Window("Containers", id: Self.dashboardWindowId, content: {
            DashboardView()
                .environment(containerManager)
                .environment(imageManager)
                .environment(volumeManager)
                .environment(builderManager)
                .environment(systemManager)
                .environment(dnsManager)
                .onAppear {
                    // Show dock icon when dashboard appears
                    NSApp.setActivationPolicy(.regular)
                }
        })
        .defaultSize(width: 800, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra(content: {
            MenuBarItem()
                .environment(systemManager)
        }, label: {
            Image(systemManager.isRunning ? "server.play" : "server.pause")
        })
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView()
                .environment(dnsManager)
                .fixedSize(horizontal: true, vertical: true)
        }
        .defaultSize(width: 600, height: 400)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }
}
