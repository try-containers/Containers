//
//  KeyValueEditor.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem

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

struct KeyValueEditor: View {
    @Binding var keyValue: KeyValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Key", text: $keyValue.key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            TextField("Value", text: $keyValue.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}
