//
//  EditableList+State.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

// MARK: - List state

extension EditableList {
    /// Which item is selected, which one is being edited, and where both
    /// land when an item is added or removed. The items themselves stay in
    /// the caller's binding; this only tracks the list's own state.
    struct State {
        /// A new item is carried here rather than looked up, because some lists
        /// only append it once the editor is saved.
        enum EditorTarget {
            case existing(Item.ID)
            case new(Item)
        }

        var selectedItemID: Item.ID?
        var editorTarget: EditorTarget?

        var isEditingNewItem: Bool {
            if case .new = editorTarget {
                return true
            }

            return false
        }

        func selectedIndex(in items: [Item]) -> [Item].Index? {
            guard let selectedItemID else {
                return nil
            }

            return items.firstIndex { $0.id == selectedItemID }
        }

        mutating func select(_ id: Item.ID?) {
            selectedItemID = id
        }

        mutating func edit(_ id: Item.ID) {
            selectedItemID = id
            editorTarget = .existing(id)
        }

        mutating func closeEditor() {
            editorTarget = nil
        }

        mutating func append(_ item: Item, to items: inout [Item]) {
            items.append(item)
            selectedItemID = item.id
        }

        mutating func remove(at index: [Item].Index, from items: inout [Item]) {
            let removedID = items[index].id
            items.remove(at: index)

            if items.isEmpty {
                selectedItemID = nil
            } else {
                // The row that moved up into the gap inherits the selection.
                selectedItemID = items[min(index, items.endIndex - 1)].id
            }

            if case .existing(removedID) = editorTarget {
                closeEditor()
            }
        }

        /// Drops a selection or an editor left pointing at an item that no longer
        /// exists, and closes the editor once a new item has been appended.
        mutating func discardStaleState(in items: [Item]) {
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

        /// An index-based binding outlives the row it was built for: after a removal
        /// SwiftUI can still evaluate the old row, and the index then reads past the
        /// end of the array. Looking the item up by id keeps that harmless, falling
        /// back to the value the row was built with.
        func binding(for id: Item.ID, in items: Binding<[Item]>) -> Binding<Item>? {
            guard let current = items.wrappedValue.first(where: { $0.id == id })
            else {
                return nil
            }

            return Binding(
                get: { items.wrappedValue.first { $0.id == id } ?? current },
                set: { updated in
                    guard
                        let index = items.wrappedValue.firstIndex(where: {
                            $0.id == id
                        })
                    else {
                        return
                    }

                    items.wrappedValue[index] = updated
                }
            )
        }
    }
}
