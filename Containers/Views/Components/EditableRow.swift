//
//  EditableRow.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct EditableRow: View {
    var text: String
    var isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text.isEmpty ? "New Item" : text)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.accentColor.opacity(0.18))
        } else {
            Color.clear
        }
    }
}
