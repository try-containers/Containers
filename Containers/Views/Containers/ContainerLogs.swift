//
//  ContainerLogsView.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import SwiftUI
import ContainerSystem

struct ContainerLogs: View {
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
            await streamLogs()
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

    private func streamLogs() async {
        let containerDir = UserDefaults.applicationDataRoot
            .appendingPathComponent("containers")
            .appendingPathComponent(containerID)
        
        let logFile = containerDir.appendingPathComponent("stdio.log")
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: logFile) else {
            return
        }
        
        // Read initial content
        if let initialData = try? fileHandle.readToEnd(),
           let initialContent = String(data: initialData, encoding: .utf8) {
            logs = initialContent.trimmingCharacters(in: .newlines)
        }
        
        // Seek to end to only get new content
        _ = try? fileHandle.seekToEnd()
        
        // Create async stream using readabilityHandler
        let stream = AsyncStream<String> { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // File truncated or handle closed
                    do {
                        _ = try fileHandle.seekToEnd()
                    } catch {
                        fileHandle.readabilityHandler = nil
                        continuation.finish()
                        return
                    }
                }
                if let newContent = String(data: data, encoding: .utf8), !newContent.isEmpty {
                    continuation.yield(newContent)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                fileHandle.readabilityHandler = nil
                try? fileHandle.close()
            }
        }
        
        // Process new log content as it arrives
        for await newContent in stream {
            if !logs.isEmpty {
                logs += newContent
            } else {
                logs = newContent.trimmingCharacters(in: .newlines)
            }
        }
    }
}
