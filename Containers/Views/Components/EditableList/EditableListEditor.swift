//
//  EditableListEditor.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import SwiftUI

struct EditableListEditor<Content: View>: View {
    var title: String
    var description: String? = nil
    var primaryButtonTitle: String = "Done"
    var showsCancelButton: Bool = false
    var isPrimaryButtonDisabled: Bool = false
    var onSave: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
            HStack {
                Spacer()
                if showsCancelButton {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(primaryButtonTitle) {
                    onSave?()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryButtonDisabled)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
