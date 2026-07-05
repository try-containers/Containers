//
//  EditableListRow.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import SwiftUI

struct EditableListRow: View {
    var values: [String]
    var isSelected: Bool = false
    var showsSelection: Bool = false
    var rowInsets: EdgeInsets? = nil
    var minHeight: CGFloat? = nil
    var onSelect: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    init(
        values: [String],
        isSelected: Bool = false,
        showsSelection: Bool = false,
        rowInsets: EdgeInsets? = nil,
        minHeight: CGFloat? = nil,
        onSelect: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.values = values
        self.isSelected = isSelected
        self.showsSelection = showsSelection
        self.rowInsets = rowInsets
        self.minHeight = minHeight
        self.onSelect = onSelect
        self.onEdit = onEdit
    }

    init(
        text: String,
        isSelected: Bool = false,
        showsSelection: Bool = false,
        rowInsets: EdgeInsets? = nil,
        minHeight: CGFloat? = nil,
        onSelect: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.init(
            values: [text],
            isSelected: isSelected,
            showsSelection: showsSelection,
            rowInsets: rowInsets,
            minHeight: minHeight,
            onSelect: onSelect,
            onEdit: onEdit
        )
    }

    var body: some View {
        rowContent
            .optionalPadding(rowInsets)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(selectionBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
            }
            .onTapGesture(count: 2) {
                onEdit?()
            }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let isEmpty = value.isEmpty

                Text(isEmpty && index == 0 ? "New Item" : value)
                    .foregroundStyle(isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if showsSelection && isSelected {
            Rectangle()
                .fill(Color.accentColor.opacity(0.18))
        } else {
            Color.clear
        }
    }
}

private extension View {
    @ViewBuilder
    func optionalPadding(_ insets: EdgeInsets?) -> some View {
        if let insets {
            padding(insets)
        } else {
            self
        }
    }
}
