//
//  ContainerLogsView.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import SwiftUI
import ContainerSystem

struct ContainerLogsView: View {
    var containerID: String

    @Environment(ContainerManager.self) private var containerManager

    @State private var logs: String = ""
    @State private var error: Error?
    @State private var showError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if logs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs Available", systemImage: "doc.text")
                } description: {
                    Text(
                        "Logs will appear here when the container generates output"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(logs)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .padding(20)
            }
        }
        .task {
            await self.getLogs()
        }
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") {
                    self.showError = false
                }
            },
            message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
        )
    }

    private func getLogs() async {
        do {
            let containerDir = UserDefaults.applicationDataRoot
                .appendingPathComponent("containers")
                .appendingPathComponent(containerID)

            self.logs = try await containerManager.getLog(
                id: containerID,
                containerDir: containerDir,
                boot: false
            )
        } catch (let error) {
            self.error = error
            self.showError = true
        }
    }
}
