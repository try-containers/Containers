//
//  KeyValuesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem

struct KeyValuesView: View {
    var keyValues: [KeyValue]
    var emptyText: String

    var leftColumnWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if keyValues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(keyValues.enumerated()), id: \.element.id) { index, keyValue in
                        HStack(alignment: .top, spacing: 16) {
                            Text(keyValue.key)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: self.leftColumnWidth, alignment: .leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(keyValue.value)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            index % 2 == 0
                                ? Color(nsColor: .controlBackgroundColor).opacity(0.3)
                                : Color.clear
                        )

                        if index < keyValues.count - 1 {
                            Divider()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
        }
    }
}

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
