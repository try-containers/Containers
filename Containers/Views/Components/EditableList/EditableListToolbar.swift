//
//  EditableListToolbar.swift
//  Containers
//

import SwiftUI

struct EditableListToolbar: View {
    var addLabel: String
    var removeLabel: String = "Remove selected row"
    var isRemoveDisabled: Bool
    var showTopDivider: Bool = false
    var backgroundColor: Color? = nil
    var add: () -> Void
    var remove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showTopDivider {
                Divider()
            }

            HStack(spacing: 0) {
                Button(action: add) {
                    toolbarIcon("plus")
                }
                .buttonStyle(.plain)
                .help(addLabel)

                Button(action: remove) {
                    toolbarIcon("minus")
                }
                .buttonStyle(.plain)
                .disabled(isRemoveDisabled)
                .help(removeLabel)

                Spacer()
            }
            .frame(height: 22)
            .background(backgroundColor ?? Color.clear)
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 20)
            .contentShape(Rectangle())
    }
}
