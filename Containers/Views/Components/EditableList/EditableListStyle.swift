//
//  EditableListStyle.swift
//  Containers
//
//  Created by Axel Martinez on 2026/08/09.
//

import SwiftUI

/// How an ``EditableList`` draws itself. The rows, the selection and the
/// add and remove controls behave the same either way.
enum EditableListStyle {
    /// Column headers over a full-height table, for wider layouts.
    case table

    /// A titled box sized to its rows, for settings panes.
    case grouped
}

private struct EditableListStyleKey: EnvironmentKey {
    static let defaultValue: EditableListStyle = .table
}

extension EnvironmentValues {
    var editableListStyle: EditableListStyle {
        get { self[EditableListStyleKey.self] }
        set { self[EditableListStyleKey.self] = newValue }
    }
}

extension View {
    func editableListStyle(_ style: EditableListStyle) -> some View {
        environment(\.editableListStyle, style)
    }
}
