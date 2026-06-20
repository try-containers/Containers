//
//  MenuBarItem.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import SwiftUI

struct MenuBarItem: View {
    @Environment(SystemManager.self) var system
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var isTogglingSystem: Bool = false
    @State private var isReloading: Bool = false

    var body: some View {
        StatusButton(isRunning: system.isRunning)

        Divider()

        MenuButton(
            title: "Dashboard",
            icon: "square.grid.2x2",
            keyEquivalent: "d"
        ) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: ContainersApp.dashboardWindowId)
        }

        MenuButton(
            title: "Settings",
            icon: "gearshape",
            keyEquivalent: ","
        ) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        MenuButton(
            title: system.isRunning ? "Stop" : "Start",
            icon: system.isRunning ? "stop.fill" : "play.fill",
            isLoading: isTogglingSystem,
            isDisabled: isTogglingSystem || isReloading
        ) {
            Task { @MainActor in
                isTogglingSystem = true

                defer { isTogglingSystem = false }

                do {
                    if system.isRunning {
                        try await system.stop()
                    } else {
                        try await system.start(
                            appRoot: UserDefaults.applicationDataRoot
                        )
                    }
                } catch {
                    openWindow(id: ContainersApp.dashboardWindowId)
                }
            }
        }

        MenuButton(
            title: "Reload",
            icon: "arrow.clockwise",
            isLoading: isReloading,
            isDisabled: isTogglingSystem || isReloading || !system.isRunning
        ) {
            Task { @MainActor in
                isReloading = true

                defer { isReloading = false }

                do {
                    try await system.stop()
                    try await system.start(
                        appRoot: UserDefaults.applicationDataRoot
                    )
                } catch {
                    openWindow(id: ContainersApp.dashboardWindowId)
                }
            }
        }

        Divider()

        MenuButton(
            title: "Quit",
            icon: "power",
            keyEquivalent: "q",
            isDisabled: isTogglingSystem || isReloading
        ) {
            Task { @MainActor in
                do {
                    try await system.stop()
                } catch {
                    print(error)
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Status Button Component

private struct StatusButton: View {
    let isRunning: Bool

    var body: some View {
        Text(statusText)
    }

    private var statusText: AttributedString {
        var statusLabel = AttributedString(isRunning ? "Running" : "Stopped")
        statusLabel.foregroundColor = .primary

        var result = AttributedString("● ")
        result.foregroundColor = isRunning ? .green : .red
        result.append(statusLabel)

        return result
    }
}

// MARK: - Menu Button Component

private struct MenuButton: View {
    let title: String
    let icon: String
    var keyEquivalent: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 14)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isHovered && !isDisabled ? .white : .primary
                    )

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else if let keyEquivalent {
                    Text("⌘\(keyEquivalent)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHovered && !isDisabled
                            ? Color.accentColor.opacity(0.15) : .clear
                    )
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
