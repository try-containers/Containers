//
//  InfoRow.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoRow: View {
    let icon: String?
    let label: String?
    let value: String
    let action: ActionButton?

    init(
        icon: String? = nil,
        label: String? = nil,
        value: String,
        action: ActionButton? = nil
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top) {
            if let icon, let label {
                Label(
                    "\(label):",
                    systemImage: icon
                )
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    width: EditableFormLayout.labelWidth,
                    alignment: .trailing
                )
                .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            } else if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(
                        width: EditableFormLayout.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            } else if let label {
                Text("\(label):")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(
                        width: EditableFormLayout.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            } else {
                Spacer()
                    .frame(width: EditableFormLayout.labelWidth)
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action {
                    action
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 22)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 12)
    }
}
