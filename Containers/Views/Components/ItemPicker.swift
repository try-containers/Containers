//
//  ItemPicker.swift
//  Containers
//
//  Created by Axel Martinez on 2026/07/18.
//

import SwiftUI

struct Item: Identifiable {
    let id: String
    let label: String
}

struct ItemPicker: View {
    let title: String
    let actionTitle: String
    let items: [Item]
    let onSelect: (Item) -> Void

    @State private var searchText = ""
    @State private var selectedID: String?

    @Environment(\.dismiss) private var dismiss

    private var filteredItems: [Item] {
        let sorted = items.sorted { $0.label < $1.label }
        guard
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return sorted
        }
        return sorted.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            filterField
            listArea
            footer
        }
        .padding()
        .frame(width: 440, height: 380)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField("Filter", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var listArea: some View {
        if filteredItems.isEmpty {
            Text("No results")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    Rectangle()
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        } else {
            List(filteredItems, selection: $selectedID) { item in
                Text(item.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .overlay(
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(actionTitle) {
                if let id = selectedID,
                    let item = filteredItems.first(where: { $0.id == id })
                {
                    onSelect(item)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedID == nil)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
