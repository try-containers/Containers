//
//  SettingsList.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct SettingsList<Item: Identifiable, EditorContent: View>: View {
    @Binding var items: [Item]

    var title: String
    var description: String
    var addLabel: String
    var allowsEditing: Bool
    var newItem: () -> Item
    var rowSummary: (Item) -> String
    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    @State private var selectedItemID: Item.ID?
    @State private var editingItemID: Item.ID?

    init(
        items: Binding<[Item]>,
        title: String,
        description: String,
        addLabel: String,
        allowsEditing: Bool = true,
        newItem: @escaping () -> Item,
        rowSummary: @escaping (Item) -> String,
        @ViewBuilder editorContent: @escaping (Binding<Item>) -> EditorContent
    ) {
        self._items = items
        self.title = title
        self.description = description
        self.addLabel = addLabel
        self.allowsEditing = allowsEditing
        self.newItem = newItem
        self.rowSummary = rowSummary
        self.editorContent = editorContent
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                // Content area
                if items.isEmpty {
                    Spacer()
                        .frame(minHeight: 80)
                } else {
                    ForEach(items) { item in
                        if let index = items.firstIndex(where: {
                            $0.id == item.id
                        }) {
                            EditableListRow(
                                text: rowSummary(items[index]),
                                isSelected: selectedItemID == item.id,
                                showsSelection: true,
                                rowInsets: EdgeInsets(
                                    top: 6,
                                    leading: 8,
                                    bottom: 6,
                                    trailing: 8
                                ),
                                minHeight: 34,
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

                if allowsEditing {
                    Divider()

                    // Bottom toolbar
                    EditableListToolbar(
                        addLabel: addLabel,
                        isRemoveDisabled: items.isEmpty || selectedItemID == nil,
                        backgroundColor: Color(nsColor: .quaternarySystemFill),
                        add: addItem,
                        remove: removeSelectedItem
                    )
                }
            }
        }
        .groupBoxStyle(SettingsListGroupBoxStyle())
        .sheet(
            isPresented: Binding(
                get: { editingItemID != nil },
                set: { isPresented in
                    if !isPresented { editingItemID = nil }
                }
            )
        ) {
            if let binding = editingItemBinding {
                EditableListEditor(title: title) {
                    editorContent(binding)
                }
            }
        }
        .onChange(of: items.count) {
            if let selectedItemID,
                !items.contains(where: { $0.id == selectedItemID })
            {
                self.selectedItemID = items.first?.id
            } else if selectedItemID == nil, !items.isEmpty {
                selectedItemID = items.first?.id
            }

            if let editingItemID,
                !items.contains(where: { $0.id == editingItemID })
            {
                self.editingItemID = nil
            }
        }
    }

    private var editingItemBinding: Binding<Item>? {
        guard let editingItemID,
            let index = items.firstIndex(where: { $0.id == editingItemID })
        else {
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
        guard let index = items.firstIndex(where: { $0.id == selectedItemID })
        else {
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

// Custom GroupBox style to remove default padding and match the screenshot
struct SettingsListGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            configuration.content
        }
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
