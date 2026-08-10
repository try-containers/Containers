//
//  EditableField.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import SwiftUI

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
    let options: [Option]
    let selection: Binding<Option>?
    let actionLabel: (() -> Label)?
    let action: (() -> Void)?
    let selectionActionTitle: String?
    let onSelectionAction: (() -> Void)?

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<Format.FormatInput>? = nil,
        format: Format? = nil,
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
        if title != nil {
            HStack(alignment: .firstTextBaseline) {
                titleLabel

                controlColumn
                    .fieldControl()
            }
        } else {
            controlColumn
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let title, let titleIcon {
            SwiftUI.Label("\(title):", systemImage: titleIcon)
        } else if let title {
            Text("\(title):")
        }
    }

    private var controlColumn: some View {
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
                    Dropdown(
                        items: selectionItems(for: selection.wrappedValue),
                        selection: selection,
                        // Sharing the column with a value field, the dropdown
                        // takes only what its content needs.
                        fillsAvailableWidth: value == nil,
                        onAction: onSelectionAction
                    )
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
    }

    private func selectionItems(
        for selected: Option
    ) -> [Dropdown<Option>.Item] {
        var items: [Dropdown<Option>.Item] = []

        // A selection that is not one of the options — no image picked yet, say
        // — still needs an entry to sit on, so show the placeholder.
        if !options.contains(selected) {
            items.append(.option(selected, title: placeholder))
            items.append(.separator)
        }

        items += options.map { option in
            .option(option, title: (option as? Unit)?.symbol ?? option.description)
        }

        if let selectionActionTitle {
            items.append(.separator)
            items.append(.action(selectionActionTitle))
        }

        return items
    }
}

// MARK: - String convenience
extension EditableField where Label == EmptyView {

    init(
        title: String? = nil,
        titleIcon: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>
    ) where Format == StringFormatStyle, Option == String {
        self.init(
            title: title,
            titleIcon: titleIcon,
            description: description,
            placeholder: placeholder,
            value: value,
            format: StringFormatStyle(),
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
            options: [],
            selection: nil,
            actionLabel: actionLabel,
            action: action
        )
    }
}
