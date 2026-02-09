//
//  ContainerSystemView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem

struct ContainerSystemView: View {
    @Environment(SystemManager.self) private var system

    var body: some View {
        ContentUnavailableView(label: {
            Label("System Is Stopped", systemImage: "exclamationmark.octagon.fill")
        },  actions: {
            Button(action: {
                Task {
                    do {
                        try await system.start(
                            appRoot: UserDefaults.applicationDataRoot
                        )
                    } catch {
                        // Error is available via system.startupError
                    }
                }
            }, label: {
                Text("Start System")
            })

        })
    }
}
