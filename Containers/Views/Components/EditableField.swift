//
//  EditableField.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import SwiftUI

struct EditableField<Label: View, Option: Hashable & CustomStringConvertible, Format: ParseableFormatStyle>: View
where Format.FormatOutput == String {
    
    let title: String?
    let titleIcon: String?
    let subtitle: String?
    let description: String?
    let placeholder: String
    let value: Binding<Format.FormatInput>
    let format: Format?
    let fieldWidth: CGFloat?
    let options: [Option]
    var selection: Binding<Option>?
    let actionLabel: (() -> Label)?
    let action: (() -> Void)?
    
    private var hasPicker: Bool { !options.isEmpty }
    
    init(
        title: String? = nil,
        titleIcon: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<Format.FormatInput>,
        format: Format? = nil,
        fieldWidth: CGFloat? = nil,
        options: [Option] = [],
        selection: Binding<Option>? = nil,
        actionLabel: (() -> Label)? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.titleIcon = titleIcon
        self.subtitle = subtitle
        self.description = description
        self.placeholder = placeholder
        self.value = value
        self.format = format
        self.fieldWidth = fieldWidth
        self.options = options
        self.selection = selection
        self.actionLabel = actionLabel
        self.action = action
    }
    
    @ViewBuilder
    private var textField: some View {
        if let format {
            TextField(placeholder, value: value, format: format)
                .textFieldStyle(.roundedBorder)
        } else if let stringValue = value as? Binding<String> {
            TextField(placeholder, text: stringValue)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    var body: some View {
        HStack {
            if let title, let titleIcon {
                SwiftUI.Label(title, systemImage: titleIcon)
            } else if let title {
                Text(title)
            }
            
            Spacer()
            
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            textField
            
            if hasPicker, let selection {
                Picker(placeholder, selection: selection) {
                    ForEach(options, id: \.self) { option in
                        if let unit = option as? Unit {
                            Text(unit.symbol).tag(option)
                        } else {
                            Text(option.description).tag(option)
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }
            
            if let action, let actionLabel {
                Button(action: action, label: actionLabel)
                    .buttonStyle(.plain)
                    .help("Choose from local images")
            }
        }
        .frame(width: fieldWidth)
        
        if let description {
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - String convenience
extension EditableField where Label == EmptyView {
    
    init(
        title: String? = nil,
        titleIcon: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        fieldWidth: CGFloat? = nil,
    ) where Format == StringFormatStyle, Option == String {
        self.init(
            title: title, titleIcon: titleIcon,
            subtitle: subtitle, description: description,
            placeholder: placeholder, value: value,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: [], selection: nil,
            actionLabel: nil, action: nil
        )
    }
    
    // String value with picker
    init(
        title: String? = nil,
        titleIcon: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        fieldWidth: CGFloat? = nil,
        options: [Option],
        selection: Binding<Option>
    ) where Format == StringFormatStyle {
        self.init(
            title: title, titleIcon: titleIcon,
            subtitle: subtitle, description: description,
            placeholder: placeholder, value: value,
            format: StringFormatStyle(),
            fieldWidth: fieldWidth,
            options: options, selection: selection,
            actionLabel: nil, action: nil
        )
    }
    
    // Typed format with picker
    init<V>(
        title: String? = nil,
        titleIcon: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<V>,
        format: Format,
        fieldWidth: CGFloat? = nil,
        options: [Option],
        selection: Binding<Option>
    ) where Format.FormatInput == V {
        self.init(
            title: title, titleIcon: titleIcon,
            subtitle: subtitle, description: description,
            placeholder: placeholder, value: value,
            format: format,
            fieldWidth: fieldWidth,
            options: options, selection: selection,
            actionLabel: nil, action: nil
        )
    }
}

extension EditableField where Option == String {
    
    // Action button, no format, no picker
    init(
        title: String? = nil,
        titleIcon: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        placeholder: String,
        value: Binding<String>,
        actionLabel: (() -> Label)? = nil,
        action: (() -> Void)? = nil
    ) where Format == StringFormatStyle {
        self.init(
            title: title, titleIcon: titleIcon,
            subtitle: subtitle, description: description,
            placeholder: placeholder, value: value,
            format: StringFormatStyle(),
            options: [], selection: nil,
            actionLabel: actionLabel, action: action
        )
    }
}

