//
//  FormStack.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

/// A sheet's form, centred on what it draws.
///
/// `Form` sizes the label column to the widest label and lines the controls up
/// under it. Sizing the stack to that and then filling the width is what
/// centres the result rather than leaving it against the leading edge.
///
/// The header sits outside the form so it can span both columns; a row inside
/// one only ever occupies the control column.
struct FormStack<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .frame(idealWidth: 0, maxWidth: .infinity)

            Form {
                content
            }
            .formStyle(.columns)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
    }
}

extension FormStack where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}

extension View {
    /// Marks this view as a form row's control.
    func fieldControl() -> some View {
        frame(width: .fieldControlWidth, alignment: .leading)
    }
}
