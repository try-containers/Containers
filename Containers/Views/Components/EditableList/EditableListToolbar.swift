//
//  EditableListToolbar.swift
//  Containers
//

import SwiftUI

struct EditableListToolbar: View {
    var addLabel: String
    var removeLabel: String = "Remove selected row"
    var isRemoveDisabled: Bool
    var showBorder: Bool = false
    var backgroundColor: Color? = nil
    var add: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                toolbarIcon("plus")
            }
            .buttonStyle(.plain)
            .help(addLabel)

            Divider()
                .frame(height: 22)

            Button(action: remove) {
                toolbarIcon("minus")
            }
            .buttonStyle(.plain)
            .disabled(isRemoveDisabled)
            .help(removeLabel)

            Spacer()
        }
        .frame(height: 26)
        .background(backgroundColor ?? Color.clear)
        .overlay {
            if showBorder {
                Rectangle()
                    .stroke(Color(nsColor: .secondarySystemFill))
            }
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: 26, height: 22)
            .contentShape(Rectangle())
    }
}
