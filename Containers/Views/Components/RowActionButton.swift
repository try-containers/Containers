//
//  RowActionButton.swift
//  Containers
//

import SwiftUI

/// An icon button in a table row.
///
/// The icons carry the app's own colours, which is what a plain button style
/// leaves alone when it is switched off, so the icon is told whether it may be
/// pressed and answers for how that looks.
struct RowActionButton: View {
    let icon: String
    let tint: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(
                    isEnabled
                        ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
