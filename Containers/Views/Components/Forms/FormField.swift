//
//  FormField.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import SwiftUI

/// A text field in a form. The placeholder is a prompt rather than a title, so
/// the enclosing `Form` does not promote it to the row's label.
struct FormField: View {
    let placeholder: String
    @Binding var value: String
    var actionIcon: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        TextField(text: $value, prompt: Text(placeholder)) {
            EmptyView()
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .overlay(alignment: .trailing) {
            if let actionIcon, let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 4)
            }
        }
    }
}
