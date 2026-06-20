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
    var columnTitles: [String] = ["Value"]
    var fieldWidth: CGFloat? = nil
    var addLabel: String
    var newItem: () -> Item
    var rowSummary: (Item) -> String
    var rowValues: ((Item) -> [String])?
    
    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    @State private var selectedItemID: Set<Item.ID> = []
    @State private var editingItemID: Item.ID?

    var body: some View {
        HStack(alignment: .top) {
            Text("\(title):")
                .frame(width: EditableFormLayout.labelWidth, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: 0) {
                    headerRow
                    
                    List(items, selection: $selectedItemID) { item in
                        row(for: item)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                editingItemID = item.id
                            }
                    }
                    .listStyle(.plain)
                    
                    toolbar
                }
                .border(Color(nsColor: .secondarySystemFill))
                .frame(minHeight: 120)
            }
            .frame(width: fieldWidth ?? EditableFormLayout.controlWidth, alignment: .leading)
        }
        .modal(isPresented: Binding(
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
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(columnTitles.enumerated()), id: \.offset) { _, columnTitle in
                Text(columnTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func row(for item: Item) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(columnTitles.indices), id: \.self) { index in
                let value = rowValue(for: item, at: index)
                let isEmpty = value.isEmpty
                
                Text(isEmpty && index == 0 ? "New Item" : value)
                    .foregroundStyle(isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func rowValue(for item: Item, at index: Int) -> String {
        let values = rowValues?(item) ?? [rowSummary(item)]
        
        guard index < values.count else {
            return ""
        }
        
        return values[index]
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
