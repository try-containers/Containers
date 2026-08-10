//
//  FieldStack.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

extension CGFloat {
    /// The fixed width of a form's control column.
    static let fieldControlWidth: CGFloat = 260
}

extension HorizontalAlignment {
    private enum FieldLabel: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.leading]
        }
    }

    /// Where a row's control starts. Rows carry it, so the stack can line their
    /// controls up without any of them knowing how wide the labels are.
    static let fieldLabel = HorizontalAlignment(FieldLabel.self)
}

/// Stacks form rows so their controls line up.
///
/// Aligning on the control's leading edge sizes the label side to the widest
/// label, which is what centres the form on what it draws rather than on a
/// share of the width it was offered.
struct FieldStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .fieldLabel, spacing: 12) {
            content
        }
        // Sized to the rows, so a filling child — the cards strip — is as wide
        // as the widest of them rather than as wide as the sheet.
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Marks this view as a form row's control, so the stack aligns to it.
    func fieldControl() -> some View {
        frame(width: .fieldControlWidth, alignment: .leading)
            .alignmentGuide(.fieldLabel) { $0[.leading] }
    }
}
