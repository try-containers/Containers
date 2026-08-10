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
}
