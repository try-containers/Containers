//
//  VolumeOverview.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/07.
//

import SwiftUI
import ContainerSystem

struct VolumeOverview: View {
    let volume: VolumeViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(rows: detailRows)
                
                if !labelRows.isEmpty {
                    InfoSection(
                        title: "Labels",
                        emptyMessage: "No labels",
                        rows: labelRows
                    )
                }
                
                if !optionRows.isEmpty {
                    InfoSection(
                        title: "Options",
                        emptyMessage: "No options",
                        rows: optionRows
                    )
                }
            }
            .padding(20)
        }
    }
    
    private var detailRows: [InfoRow] {
        [
            InfoRow(label: "Name", value: volume.name),
            InfoRow(label: "Type", value: volume.volumeType.rawValue),
            InfoRow(label: "State", value: volume.inUse ? "In use" : "Unused"),
            InfoRow(label: "Size", value: volume.formattedSize ?? "N/A"),
            InfoRow(label: "Created", value: volume.formattedCreated),
            InfoRow(label: "Driver", value: volume.driver),
            InfoRow(label: "Format", value: volume.format),
            InfoRow(label: "Source", value: volume.source.nilIfEmpty ?? "N/A")
        ]
    }
    
    private var labelRows: [InfoRow] {
        volume.labels
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { InfoRow(label: $0.key, value: $0.value) }
    }
    
    private var optionRows: [InfoRow] {
        volume.options
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { InfoRow(label: $0.key, value: $0.value) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
