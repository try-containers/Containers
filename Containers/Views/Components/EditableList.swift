//
//  EditableList.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct EditableList<Item: Identifiable, EditorContent: View>: View {
    @Binding var items: [Item]

    var title: String
    var addLabel: String
    var newItem: () -> Item
    var rowSummary: (Item) -> String
    
    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    @State private var selectedItemID: Set<Item.ID> = []
    @State private var editingItemID: Item.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Table(items, selection: $selectedItemID) {
                TableColumn(title) { item in
                    Text(rowSummary(item).isEmpty ? "New Item" : rowSummary(item))
                        .foregroundStyle(rowSummary(item).isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture(count: 2) {
                            editingItemID = item.id
                        }
                }
            }
            .border(Color(nsColor: .secondarySystemFill))
            .frame(minHeight: 120)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                toolbar
            }
        }
        .sheet(isPresented: Binding(
            get: { editingItemID != nil },
            set: { if !$0 { editingItemID = nil } }
        )) {
            if let binding = editingItemBinding {
                EditableListItemEditor(title: title) {
                    editorContent(binding)
                }
            }
        }
        .onChange(of: items.count) {
            selectedItemID = selectedItemID.filter { id in
                items.contains(where: { $0.id == id })
            }
            if let editingItemID, !items.contains(where: { $0.id == editingItemID }) {
                self.editingItemID = nil
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: addItem) {
                Image(systemName: "plus")
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help(addLabel)

            Divider()
                .frame(height: 22)

            Button(action: removeSelectedItems) {
                Image(systemName: "minus")
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(selectedItemID.isEmpty)
            .help("Remove selected rows")

            Spacer()
        }
        .frame(height: 26)
        .border(Color(nsColor: .secondarySystemFill))
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
        selectedItemID = [item.id]
        editingItemID = item.id
    }

    private func removeSelectedItems() {
        items.removeAll { selectedItemID.contains($0.id) }
    }
}
