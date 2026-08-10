//
//  EditableList+Editor.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

// MARK: - Editor sheet

extension EditableList {
    var editorPresentation: Binding<Bool> {
        Binding(
            get: { state.editorTarget != nil },
            set: { isPresented in
                if !isPresented {
                    closeEditor()
                }
            }
        )
    }

    @ViewBuilder
    var editor: some View {
        if let binding = editorItemBinding {
            FormSheet(
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

    var isEditingNewItem: Bool {
        if case .new = state.editorTarget {
            return true
        }

        return false
    }

    var editorPrimaryButtonTitle: String {
        isEditingNewItem ? "Save" : "Done"
    }

    var editorTitle: String {
        isEditingNewItem ? addLabel : (title ?? addLabel)
    }

    var editorSaveAction: (() -> Void)? {
        guard isEditingNewItem else {
            return nil
        }

        return saveNewEditingItem
    }

    var editorItemBinding: Binding<Item>? {
        guard let target = state.editorTarget else {
            return nil
        }

        switch target {
        case .new:
            return Binding(
                get: {
                    guard case .new(let item) = self.state.editorTarget else {
                        return newItem()
                    }

                    return item
                },
                set: { state.editorTarget = .new($0) }
            )
        case .existing(let id):
            return state.binding(for: id, in: $items)
        }
    }

    func openEditor(for id: Item.ID) {
        state.edit(id)
    }

    func closeEditor() {
        state.closeEditor()
    }

    func saveNewEditingItem() {
        guard case .new(let item) = state.editorTarget else {
            return
        }

        state.append(item, to: &items)
        state.closeEditor()
    }
}
