//
//  CGFloat+ButtonWidth.swift
//  Containers
//
//  Created by Axel Martinez on 10/08/2026.
//

import Foundation

extension CGFloat {
    /// A sheet's buttons are all one width, matching each other rather than
    /// their titles. It goes on the label: a macOS button keeps its intrinsic
    /// width whatever frame it is given, and adds about 24pt around the label.
    static let sheetButtonLabelWidth: CGFloat = 64

    /// The fixed width of a form's control column.
    static let fieldControlWidth: CGFloat = 260

    /// The gap between the mark on a sheet's centre line — the progress
    /// spinner, or the mark that a failure leaves in its place — and the
    /// writing hung beneath it.
    static let sheetMarkSpacing: CGFloat = 12
}
