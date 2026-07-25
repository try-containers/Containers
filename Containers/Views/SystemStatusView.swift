//
//  SystemStatusView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import SwiftUI

struct SystemStatusView: View {
    @Environment(SystemManager.self) private var system

    var body: some View {
        switch system.status {
        case .starting:
            startingView
        case .stopping:
            stoppingView
        case .failed:
            failedView
        case .notStarted:
            stoppedView
        case .running:
            EmptyView()
        }
    }

    private var startingView: some View {
        ContentUnavailableView(
            label: {
                ProgressView()
                    .controlSize(.large)
                    .padding(.bottom, 4)
                Text("Starting Container System…")
            },
            description: {
                Text("Please wait while the container system initializes.")
            }
        )
    }

    private var stoppingView: some View {
        ContentUnavailableView(
            label: {
                ProgressView()
                    .controlSize(.large)
                    .padding(.bottom, 4)
                Text("Stopping Container System…")
            },
            description: {
                Text("Please wait while the container system shuts down.")
            }
        )
    }

    private var failedView: some View {
        ContentUnavailableView(
            label: {
                Label(
                    "System Failed to Start",
                    systemImage: "exclamationmark.triangle.fill"
                )
            },
            description: {
                if let error = system.startupError {
                    Text(error.localizedDescription)
                }
            },
            actions: {
                Button(
                    action: {
                        Task {
                            do {
                                try await system.start(
                                    appRoot: UserDefaults.applicationDataRoot
                                )
                            } catch {
                                // Error is available via system.startupError
                            }
                        }
                    },
                    label: {
                        Text("Retry")
                    }
                )
            }
        )
    }

    private var stoppedView: some View {
        ContentUnavailableView(
            label: {
                Label(
                    "System Is Stopped",
                    systemImage: "exclamationmark.octagon.fill"
                )
            },
            actions: {
                Button(
                    action: {
                        Task {
                            do {
                                try await system.start(
                                    appRoot: UserDefaults.applicationDataRoot
                                )
                            } catch {
                                // Error is available via system.startupError
                            }
                        }
                    },
                    label: {
                        Text("Start System")
                    }
                )
            }
        )
    }
}
