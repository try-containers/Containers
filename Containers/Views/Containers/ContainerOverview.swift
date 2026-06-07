//
//  ContainerOverview.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import SwiftUI
import Containerization
import ContainerizationOCI
import ContainerSystem

struct ContainerOverview: View {
    let snapshot: ContainerSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(rows: detailRows)

                if portsSummary.count > 0 {
                    InfoSection(rows: [InfoRow(label: "Ports", value: portsSummary)])
                }
                
                if labelRows.count > 0 {
                    InfoSection(
                        title: "Labels",
                        emptyMessage: "No labels",
                        rows: labelRows
                    )
                }
            }
            .padding(20)
        }
    }

    private var detailRows: [InfoRow] {
        [
            InfoRow(label: "ID", value: snapshot.id),
            InfoRow(label: "Image", value: snapshot.configuration.image.reference),
            InfoRow(label: "OS", value: osSummary),
            InfoRow(label: "Arch", value: snapshot.configuration.platform.architecture),
            InfoRow(label: "Command", value: commandSummary),
            InfoRow(label: "Last Started", value: startedAtSummary)
        ]
    }

    private var labelRows: [InfoRow] {
        snapshot.configuration.labels
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { InfoRow(label: $0.key, value: $0.value) }
    }

    private var osSummary: String {
        snapshot.configuration.platform.os.localizedCapitalized
    }

    private var commandSummary: String {
        let process = snapshot.configuration.initProcess
        let executable = process.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = process.arguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ([executable] + arguments)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? "N/A"
    }

    private var portsSummary: String {
        let ports = snapshot.configuration.publishedPorts.map(\.description)
        let sockets = snapshot.configuration.publishedSockets.map {
            "\($0.hostPath) -> \($0.containerPath)"
        }

        return (ports + sockets).joined(separator: ", ").nilIfEmpty ?? "N/A"
    }

    private var startedAtSummary: String {
        guard let startedDate = snapshot.startedDate else {
            return "N/A"
        }

        return Self.relativeFormatter.localizedString(for: startedDate, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
