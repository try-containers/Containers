//
//  EditableList.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

private struct EditableListCellPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 8
}

private struct EditableListRowIsSelectedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var editableListCellPadding: CGFloat {
        get { self[EditableListCellPaddingKey.self] }
        set { self[EditableListCellPaddingKey.self] = newValue }
    }

    var editableListRowIsSelected: Bool {
        get { self[EditableListRowIsSelectedKey.self] }
        set { self[EditableListRowIsSelectedKey.self] = newValue }
    }
}

private enum EditableListEditorTarget<ID: Hashable, Item> {
    case existing(ID)
    case new(Item)
}

struct EditableList<Item: Identifiable, RowContent: View, EditorContent: View>:
    View
where Item.ID: Hashable {
    @Binding var items: [Item]

    var title: String?
    var description: String? = nil
    var editorDescription: String? = nil
    var columnTitles: [String] = ["Value"]
    var fieldWidth: CGFloat? = nil
    var addLabel: String
    var emptyMessage: String
    var hasContentBelow: Bool
    var newItem: () -> Item
    var rowSummary: (Item) -> String
    var rowValues: ((Item) -> [String])?
    var rowContent: ((Binding<Item>) -> RowContent)?
    var canSave: (Item) -> Bool = { _ in true }

    @ViewBuilder var editorContent: (Binding<Item>) -> EditorContent

    init(
        items: Binding<[Item]>,
        title: String? = nil,
        description: String? = nil,
        editorDescription: String? = nil,
        columnTitles: [String] = ["Value"],
        fieldWidth: CGFloat? = nil,
        addLabel: String,
        emptyMessage: String,
        hasContentBelow: Bool = false,
        newItem: @escaping () -> Item,
        rowSummary: @escaping (Item) -> String,
        rowValues: ((Item) -> [String])? = nil,
        rowContent: ((Binding<Item>) -> RowContent)? = nil,
        canSave: @escaping (Item) -> Bool = { _ in true },
        @ViewBuilder editorContent: @escaping (Binding<Item>) -> EditorContent
    ) {
        self._items = items
        self.title = title
        self.description = description
        self.editorDescription = editorDescription
        self.columnTitles = columnTitles
        self.fieldWidth = fieldWidth
        self.addLabel = addLabel
        self.emptyMessage = emptyMessage
        self.hasContentBelow = hasContentBelow
        self.newItem = newItem
        self.rowSummary = rowSummary
        self.rowValues = rowValues
        self.rowContent = rowContent
        self.canSave = canSave
        self.editorContent = editorContent
    }

    @State private var selectedItemID: Item.ID?
    @State private var editorTarget: EditableListEditorTarget<Item.ID, Item>?
    @State private var isExpanded: Bool = true

    private var usesModalEditor: Bool {
        rowContent == nil
    }

    var body: some View {
        content
            .environment(\.editableListCellPadding, 8)
            .sheet(isPresented: editorPresentation) {
                editor
            }
            .onChange(of: items.endIndex) { _, _ in
                removeStaleState()
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                disclosureHeader(title: title)
                    .padding(.vertical, 8)
            }

            if isExpanded || title == nil {
                VStack(spacing: 0) {
                    table

                    if title != nil {
                        Divider()
                    }

                    EditableListToolbar(
                        addLabel: addLabel,
                        isRemoveDisabled: items.isEmpty,
                        add: addItem,
                        remove: removeSelectedItem
                    )
                    .padding(.leading, title == nil ? 4 : 0)
                }
                .frame(maxHeight: title == nil ? .infinity : nil)
                .padding(.leading, title != nil ? 18 : 0)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if (title != nil && !isExpanded) || hasContentBelow {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: title == nil ? .infinity : nil, alignment: .leading)
    }

    private func disclosureHeader(title: String) -> some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName: isExpanded ? "chevron.down" : "chevron.right"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)

                Text(title)
                    .font(.headline)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columnTitles.enumerated()), id: \.offset) {
                    index,
                    columnTitle in
                    Text(columnTitle)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.leading, title == nil ? 12 : 8)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if index < columnTitles.count - 1 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 22)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List($items, selection: $selectedItemID) { $item in
                    row(for: $item)
                        .environment(
                            \.editableListRowIsSelected,
                            selectedItemID == item.id
                        )
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                selectedItemID = item.id
                            }
                        )
                        .onTapGesture(count: 2) {
                            if usesModalEditor {
                                openEditor(for: item.id)
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minHeight: 120)
    }

    private func row(for item: Binding<Item>) -> some View {
        Group {
            if let rowContent {
                rowContent(item)
            } else {
                EditableListRow(values: rowValues(for: item.wrappedValue))
            }
        }
    }

    private func rowValues(for item: Item) -> [String] {
        let values = rowValues?(item) ?? [rowSummary(item)]

        return columnTitles.indices.map { index in
            guard index < values.count else {
                return ""
            }

            return values[index]
        }
    }

    private var editorPresentation: Binding<Bool> {
        Binding(
            get: { editorTarget != nil },
            set: { isPresented in
                if !isPresented {
                    closeEditor()
                }
            }
        )
    }

    @ViewBuilder
    private var editor: some View {
        if let binding = editorItemBinding {
            EditableListEditor(
                title: editorTitle,
                description: editorDescription,
                primaryButtonTitle: editorPrimaryButtonTitle,
                showsCancelButton: isEditingNewItem,
                isPrimaryButtonDisabled: !canSave(binding.wrappedValue),
                onSave: editorSaveAction
            ) {
                editorContent(binding)
            }
        }
    }

    private var isEditingNewItem: Bool {
        if case .new = editorTarget {
            return true
        }

        return false
    }

    private var editorPrimaryButtonTitle: String {
        isEditingNewItem ? "Save" : "Done"
    }

    private var editorTitle: String {
        isEditingNewItem ? addLabel : (title ?? addLabel)
    }

    private var editorSaveAction: (() -> Void)? {
        guard isEditingNewItem else {
            return nil
        }

        return saveNewEditingItem
    }

    private var editorItemBinding: Binding<Item>? {
        guard let target = editorTarget else {
            return nil
        }

        switch target {
        case .new:
            return Binding(
                get: {
                    guard case .new(let item) = self.editorTarget else {
                        return newItem()
                    }

                    return item
                },
                set: { editorTarget = .new($0) }
            )
        case .existing(let id):
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return nil
            }

            return Binding(
                get: { items[index] },
                set: { items[index] = $0 }
            )
        }
    }

    private func addItem() {
        let item = newItem()
        if usesModalEditor {
            editorTarget = .new(item)
        } else {
            items.append(item)
            selectedItemID = item.id
        }
    }

    private func openEditor(for id: Item.ID) {
        selectedItemID = id
        editorTarget = .existing(id)
    }

    private func closeEditor() {
        editorTarget = nil
    }

    private func saveNewEditingItem() {
        guard case .new(let item) = editorTarget else {
            return
        }

        items.append(item)
        selectedItemID = item.id
        closeEditor()
    }

    private func removeStaleState() {
        if let selectedItemID,
            !items.contains(where: { $0.id == selectedItemID })
        {
            self.selectedItemID = nil
        }

        switch editorTarget {
        case .existing(let id) where !items.contains(where: { $0.id == id }):
            closeEditor()
        case .new(let item) where items.contains(where: { $0.id == item.id }):
            closeEditor()
        case .existing, .new, nil:
            break
        }
    }

    private func removeSelectedItem() {
        guard let index = selectedItemIndex ?? items.indices.last else {
            return
        }

        removeItem(at: index)
    }

    private var selectedItemIndex: [Item].Index? {
        guard let selectedItemID else {
            return nil
        }

        return items.firstIndex { $0.id == selectedItemID }
    }

    private func removeItem(at index: [Item].Index) {
        let removedID = items[index].id
        items.remove(at: index)

        if items.isEmpty {
            selectedItemID = nil
        } else {
            selectedItemID = items[min(index, items.endIndex - 1)].id
        }

        if case .existing(removedID) = editorTarget {
            closeEditor()
        }
    }
}

extension EditableList where RowContent == EmptyView {
    init(
        items: Binding<[Item]>,
        title: String? = nil,
        description: String? = nil,
        editorDescription: String? = nil,
        columnTitles: [String] = ["Value"],
        fieldWidth: CGFloat? = nil,
        addLabel: String,
        emptyMessage: String,
        hasContentBelow: Bool = false,
        newItem: @escaping () -> Item,
        rowSummary: @escaping (Item) -> String,
        rowValues: ((Item) -> [String])? = nil,
        canSave: @escaping (Item) -> Bool = { _ in true },
        @ViewBuilder editorContent: @escaping (Binding<Item>) -> EditorContent
    ) {
        self.init(
            items: items,
            title: title,
            description: description,
            editorDescription: editorDescription,
            columnTitles: columnTitles,
            fieldWidth: fieldWidth,
            addLabel: addLabel,
            emptyMessage: emptyMessage,
            hasContentBelow: hasContentBelow,
            newItem: newItem,
            rowSummary: rowSummary,
            rowValues: rowValues,
            rowContent: nil,
            canSave: canSave,
            editorContent: editorContent
        )
    }
}
