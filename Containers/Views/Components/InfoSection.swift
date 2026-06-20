//
//  InfoSection.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoSection: View {
    let title: String?
    let subtitle: String?
    let emptyImage: String?
    let emptyMessage: String?
    let rows: [InfoRow]

    init(
        title: String? = nil,
        subtitle: String? = nil,
        emptyImage: String? = nil,
        emptyMessage: String? = nil,
        rows: [InfoRow]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.emptyImage = emptyImage
        self.emptyMessage = emptyMessage
        self.rows = rows
    }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                if let emptyImage {
                    Image(systemName: emptyImage)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }

                if let emptyMessage {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(rowItems) { item in
                    item.row
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var rowItems: [InfoSectionRowItem] {
        rows.indices.map { index in
            InfoSectionRowItem(id: index, row: rows[index])
        }
    }
}

private struct InfoSectionRowItem: Identifiable {
    let id: Int
    let row: InfoRow
}

#Preview {
    InfoSection(
        title: "Test Section",
        subtitle: "Test subtitle",
        rows: [
            InfoRow(label: "Test title", value: "Test vaue"),
            InfoRow(label: "Test title 2", value: "Test value 2"),
        ]
    )
}
