//
//  EditableField.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//
import SwiftUI

enum EditableFormLayout {
    static let labelWidth: CGFloat = 150
    static let controlWidth: CGFloat = 260
    static let fieldLabelTopPadding: CGFloat = 5
}

struct EditableField<
    Label: View,
    Option: Hashable & CustomStringConvertible,
    Format: ParseableFormatStyle
>: View
where Format.FormatOutput == String {

    let title: String?
    let titleIcon: String?
    let description: String?
    let placeholder: String
    let value: Binding<Format.FormatInput>?
    let format: Format?
    let fieldWidth: CGFloat?
    let options: [Option]
    let selection: Binding<Option>?
    let actionLabel: (() -> Label)?
    let action: (() -> Void)?
    let selectionActionTitle: String?
    let onSelectionAction: (() -> Void)?

    private let editableFieldActionSentinel = "§__editablefield_action__§"

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<Format.FormatInput>? = nil,
        format: Format? = nil,
        fieldWidth: CGFloat? = nil,
        options: [Option] = [],
        selection: Binding<Option>? = nil,
        actionLabel: (() -> Label)? = nil,
        action: (() -> Void)? = nil,
        selectionActionTitle: String? = nil,
        onSelectionAction: (() -> Void)? = nil
    ) {
        precondition(
            value != nil || selection != nil,
            "EditableField requires either a value binding or a selection binding."
        )

        self.title = title
        self.titleIcon = titleIcon
        self.description = description
        self.placeholder = placeholder
        self.value = value
        self.format = format
        self.fieldWidth = fieldWidth
        self.options = options
        self.selection = selection
        self.actionLabel = actionLabel
        self.action = action
        self.selectionActionTitle = selectionActionTitle
        self.onSelectionAction = onSelectionAction
    }

    @ViewBuilder
    private func title(for value: Binding<Format.FormatInput>) -> some View {
        if let format {
            TextField(placeholder, value: value, format: format)
                .textFieldStyle(.roundedBorder)
        } else if let stringValue = value as? Binding<String> {
            TextField(placeholder, text: stringValue)
                .textFieldStyle(.roundedBorder)
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            if let title, let titleIcon {
                SwiftUI.Label("\(title):", systemImage: titleIcon)
                    .frame(
                        width: EditableFormLayout.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            } else if let title {
                Text("\(title):")
                    .frame(
                        width: EditableFormLayout.labelWidth,
                        alignment: .trailing
                    )
                    .padding(.top, EditableFormLayout.fieldLabelTopPadding)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    if let value {
                        title(for: value)
                            .overlay(alignment: .trailing) {
                                if let action, let actionLabel {
                                    Button(action: action, label: actionLabel)
                                        .buttonStyle(.borderless)
                                        .padding(.trailing, 4)
                                }
                            }
                    }

                    if let selection {
                        Picker(placeholder, selection: selection) {
                            if !options.contains(selection.wrappedValue) {
                                Text(placeholder).tag(selection.wrappedValue)
                                Divider()
                            }
                            ForEach(options, id: \.self) { option in
                                if let unit = option as? Unit {
                                    Text(unit.symbol).tag(option)
                                } else {
                                    Text(option.description).tag(option)
                                }
                            }
                            if let actionTitle = selectionActionTitle,
                                let sentinel = editableFieldActionSentinel
                                    as? Option
                            {
                                Divider()
                                Text(actionTitle).tag(sentinel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onChange(of: selection.wrappedValue) { old, new in
                            if (new as? String) == editableFieldActionSentinel {
                                selection.wrappedValue = old
                                onSelectionAction?()
                            }
                        }
                    }

                    if value == nil, let action, let actionLabel {
                        Button(action: action, label: actionLabel)
                            .buttonStyle(.plain)
                    }
                }

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(
                maxWidth: fieldWidth ?? EditableFormLayout.controlWidth,
                alignment: .leading
            )
        }
    }
}

// MARK: - String convenience
extension EditableField where Label == EmptyView {

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        fieldWidth: CGFloat? = nil
    ) where Format == StringFormatStyle, Option == String {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: value,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: [],
            selection: nil,
            actionLabel: nil,
            action: nil
        )
    }

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        fieldWidth: CGFloat? = nil,
        options: [Option],
        selection: Binding<Option>
    ) where Format == StringFormatStyle {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: value,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: options,
            selection: selection,
            actionLabel: nil,
            action: nil
        )
    }

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        fieldWidth: CGFloat? = nil,
        options: [Option],
        selection: Binding<Option>,
        selectionActionTitle: String? = nil,
        onSelectionAction: (() -> Void)? = nil
    ) where Format == StringFormatStyle, Format.FormatInput == String {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: nil,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: options,
            selection: selection,
            actionLabel: nil,
            action: nil,
            selectionActionTitle: selectionActionTitle,
            onSelectionAction: onSelectionAction
        )
    }

    init<V>(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<V>,
        format: Format,
        fieldWidth: CGFloat? = nil,
        options: [Option] = [],
        selection: Binding<Option>? = nil
    ) where Format.FormatInput == V {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: value,
            format: format,
            fieldWidth: fieldWidth,
            options: options,
            selection: selection,
            actionLabel: nil,
            action: nil
        )
    }
}

extension EditableField where Option == String {

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        fieldWidth: CGFloat? = nil,
        actionLabel: (() -> Label)? = nil,
        action: (() -> Void)? = nil
    ) where Format == StringFormatStyle {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: value,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: [],
            selection: nil,
            actionLabel: actionLabel,
            action: action
        )
    }
}
