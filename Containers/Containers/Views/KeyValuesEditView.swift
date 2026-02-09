//
//  KeyValuesEditView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem

struct KeyValuesEditView: View {
    @Binding var keyValues: [KeyValue]
    
    var title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("key=value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Empty keys will be removed when creating")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Empty state
            if keyValues.isEmpty {
                Button(action: {
                    self.keyValues.append(.init())
                }) {
                    Label("Add Key-Value Pair", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // Key-Value rows
            VStack(spacing: 6) {
                ForEach($keyValues) { $keyValue in
                    HStack(spacing: 8) {
                        TextField("key", text: $keyValue.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("=")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                        
                        TextField("value", text: $keyValue.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        HStack(spacing: 4) {
                            Button(action: {
                                self.keyValues.append(.init())
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Add another key-value pair")
                            
                            Button(action: {
                                self.keyValues.removeAll(where: { $0.id == keyValue.id })
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this key-value pair")
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }
}
