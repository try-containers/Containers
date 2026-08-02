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
    static let rowSpacing: CGFloat = 8

    /// Share of the width left over by the control that goes to the label side.
    /// Measured off Xcode's scheme sheet, which gives the label a little more
    /// than the trailing margin and so sits the control just right of centre.
    static let labelShare: CGFloat = 0.57
}

/// A form row laid out the way AppKit does it: the control keeps a fixed width
/// and the label hangs off its leading edge, rather than the label and control
/// centring together as one block.
///
/// This is a `Layout` rather than an `HStack` because the leftover width is
/// split unevenly. Flexible frames can only divide it equally — and a `Spacer`
/// cannot even do that, since it yields to a `maxWidth: .infinity` sibling.
struct EditableFormRow<Label: View, Control: View>: View {
    var controlWidth: CGFloat = EditableFormLayout.controlWidth
    @ViewBuilder var label: Label
    @ViewBuilder var control: Control

    var body: some View {
        EditableFormRowLayout(
            controlWidth: controlWidth,
            spacing: EditableFormLayout.rowSpacing,
            labelShare: EditableFormLayout.labelShare
        ) {
            label
                .padding(.top, EditableFormLayout.fieldLabelTopPadding)
                .frame(maxWidth: .infinity, alignment: .trailing)

            control
                .frame(width: controlWidth, alignment: .leading)
        }
    }
}

private struct EditableFormRowLayout: Layout {
    let controlWidth: CGFloat
    let spacing: CGFloat
    let labelShare: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let label = subviews.first, let control = subviews.last,
            subviews.count == 2
        else { return .zero }

        let width =
            proposal.width
            ?? label.sizeThatFits(.unspecified).width + spacing + controlWidth
        let labelWidth = labelWidth(for: width)

        let height = max(
            label.sizeThatFits(.init(width: labelWidth, height: nil)).height,
            control.sizeThatFits(.init(width: controlWidth, height: nil)).height
        )

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let label = subviews.first, let control = subviews.last,
            subviews.count == 2
        else { return }

        let labelWidth = labelWidth(for: bounds.width)

        label.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: .init(width: labelWidth, height: nil)
        )

        control.place(
            at: CGPoint(x: bounds.minX + labelWidth + spacing, y: bounds.minY),
            proposal: .init(width: controlWidth, height: nil)
        )
    }

    private func labelWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - controlWidth - spacing) * labelShare)
    }
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
        if title != nil {
            EditableFormRow(
                controlWidth: fieldWidth ?? EditableFormLayout.controlWidth,
                label: { titleLabel },
                control: { controlColumn }
            )
        } else {
            controlColumn
                .frame(
                    maxWidth: fieldWidth ?? EditableFormLayout.controlWidth,
                    alignment: .leading
                )
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
                    FormPopUpButton(
                        items: selectionItems(for: selection.wrappedValue),
                        selection: selection,
                        // Sharing the column with a value field, the pop-up
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
    ) -> [FormPopUpButton<Option>.Item] {
        var items: [FormPopUpButton<Option>.Item] = []

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
