//
//  EditableListSection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct EditableListSection<Item: Identifiable, EditorContent: View>: View {
    @Binding var items: [Item]

    var title: String
    var description: String
    var addLabel: String
    var newItem: () -> Item
    var rowSummary: (Item) -> String
    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    @State private var selectedItemID: Item.ID?
    @State private var editingItemID: Item.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        Text(addLabel)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(items) { item in
                            if let index = items.firstIndex(where: { $0.id == item.id }) {
                                EditableRow(
                                    text: rowSummary(items[index]),
                                    isSelected: selectedItemID == item.id,
                                    onSelect: {
                                        selectedItemID = item.id
                                    },
                                    onEdit: {
                                        selectedItemID = item.id
                                        editingItemID = item.id
                                    }
                                )

                                if index < items.count - 1 {
                                    Divider()
                                        .padding(.leading, 8)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 36, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor))

                Divider()

                HStack(spacing: 0) {
                    Button(action: addItem) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(addLabel)

                    Divider()
                        .frame(height: 20)

                    Button(action: removeSelectedItem) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(items.isEmpty || selectedItemID == nil)
                    .help("Remove selected row")

                    Spacer()
                }
                .frame(height: 22)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingItemID != nil },
            set: { isPresented in
                if !isPresented {
                    editingItemID = nil
                }
            }
        )) {
            if let binding = editingItemBinding {
                EditableListItemEditor(title: title) {
                    editorContent(binding)
                }
            }
        }
        .onChange(of: items.count) {
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = items.first?.id
            } else if selectedItemID == nil, !items.isEmpty {
                selectedItemID = items.first?.id
            }

            if let editingItemID, !items.contains(where: { $0.id == editingItemID }) {
                self.editingItemID = nil
            }
        }
    }

    private var editingItemBinding: Binding<Item>? {
        guard let editingItemID,
              let index = items.firstIndex(where: { $0.id == editingItemID }) else {
            return nil
        }

        return Binding(
            get: { items[index] },
            set: { items[index] = $0 }
        )
    }

    private func addItem() {
        let item = newItem()
        items.append(item)
        selectedItemID = item.id
        editingItemID = item.id
    }

    private func removeSelectedItem() {
        guard let selectedItemID else { return }
        guard let index = items.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }

        items.remove(at: index)

        if items.isEmpty {
            self.selectedItemID = nil
        } else {
            let nextIndex = min(index, items.count - 1)
            self.selectedItemID = items[nextIndex].id
        }
    }
}

private struct EditableListItemEditor<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            content

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
