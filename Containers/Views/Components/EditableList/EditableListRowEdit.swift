//
//  EditableListRowEdit.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import SwiftUI

func keyValueSummary(_ keyValue: KeyValue) -> String {
    let key = keyValue.key.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = keyValue.value.trimmingCharacters(in: .whitespacesAndNewlines)

    if key.isEmpty && value.isEmpty {
        return "New Item"
    }

    if value.isEmpty {
        return key
    }

    if key.isEmpty {
        return value
    }

    return "\(key)=\(value)"
}

struct EditableListRowEdit: View {
    struct Field: Identifiable {
        let id = UUID()
        var placeholder: String
        var text: Binding<String>
        var isMonospaced: Bool = false
    }

    var fields: [Field]

    @Environment(\.editableListCellPadding) private var cellPadding
    @Environment(\.editableListRowIsSelected) private var isRowSelected

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                TextField(field.placeholder, text: field.text)
                    .textFieldStyle(.plain)
                    .font(
                        field.isMonospaced
                            ? .system(.body, design: .monospaced)
                            : .body
                    )
                    .foregroundStyle(isRowSelected ? Color.white : Color.primary)
                    .padding(.horizontal, cellPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if index < fields.count - 1 {
                    Divider()
                }
            }
        }
    }
}
