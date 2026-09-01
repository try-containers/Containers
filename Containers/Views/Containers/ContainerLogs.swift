//
//  ContainerLogsView.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import ContainerSystem
import SwiftUI

struct ContainerLogs: View {
    var containerID: String

    @Environment(ContainerManager.self) private var containerManager

    @State private var logs: String = ""
    @State private var bootLog: String = ""
    @State private var source: Source = .output
    @State private var hasLoaded: Bool = false
    @State private var errorAlert: ErrorAlert?

    private enum Source: String, CaseIterable, Identifiable {
        case output = "Output"
        case boot = "Boot"

        var id: String { rawValue }

        var emptyMessage: String {
            switch self {
            case .output:
                "Logs will appear here when the container generates output"
            case .boot:
                "The boot log is written while the container starts up"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Log", selection: $source) {
                ForEach(Source.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .frame(maxWidth: .infinity)

            if !hasLoaded {
                // Hidden by the window until ready, so nothing to draw.
                Color.clear
            } else if selectedLogs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs Available", systemImage: "doc.text")
                } description: {
                    Text(source.emptyMessage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                terminal
            }
        }
        .padding(20)
        .contentReady(hasLoaded)
        .task {
            await streamLogs()
        }
        .task(id: source) {
            guard source == .boot else { return }
            bootLog = Self.read(Self.bootLogFile(for: containerID))
        }
        .errorAlert($errorAlert)
    }

    private var terminal: some View {
        ScrollView {
            Text(selectedLogs)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var selectedLogs: String {
        switch source {
        case .output:
            logs
        case .boot:
            bootLog
        }
    }

    private static func bootLogFile(for containerID: String) -> URL {
        UserDefaults.applicationDataRoot
            .appendingPathComponent("containers")
            .appendingPathComponent(containerID)
            .appendingPathComponent("vminitd.log")
    }

    private static func read(_ file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8))?
            .trimmingCharacters(in: .newlines) ?? ""
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
            // Nothing to read, but the tab is done waiting.
            hasLoaded = true
            return
        }

        // Read initial content
        if let initialData = try? fileHandle.readToEnd(),
            let initialContent = String(data: initialData, encoding: .utf8)
        {
            logs = initialContent.trimmingCharacters(in: .newlines)
        }

        // The tail arrives live from here, growing the tab rather than
        // deciding its height.
        hasLoaded = true

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
                if let newContent = String(data: data, encoding: .utf8),
                    !newContent.isEmpty
                {
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
