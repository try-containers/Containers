//
//  EditableListSection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct EditableListSection<Item: Identifiable, RowContent: View>: View {
    @Binding var items: [Item]

    var title: String
    var formatHint: String
    var description: String
    var addLabel: String
    var newItem: () -> Item
    @ViewBuilder var rowContent: (Binding<Item>) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formatHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Empty state
            if items.isEmpty {
                Button {
                    items.append(newItem())
                } label: {
                    Label(addLabel, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            // Rows
            VStack(spacing: 6) {
                ForEach(items) { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        EditableRow(content: {
                            rowContent($items[index])
                        }, onAdd: {
                            items.append(newItem())
                        }, onDelete: {
                            let id = item.id
                            items.removeAll(where: { $0.id == id })
                        })
                    }
                }
            }
        }
    }
}
