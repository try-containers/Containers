//
//  View+PopoverTip.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import SwiftUI
import TipKit

extension View {
    /// A popover tip the caller may not have, for a view built from data that
    /// carries its tip optionally.
    @ViewBuilder
    func popoverTipIfPresent<T: Tip>(
        _ tip: T?,
        arrowEdge: Edge? = nil
    ) -> some View {
        if let tip {
            self.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }

    /// A popover tip shown only under some condition, for a tip that is always
    /// present but not always applicable.
    @ViewBuilder
    func popoverTip<T: Tip>(
        _ tip: T,
        when condition: Bool,
        arrowEdge: Edge? = nil
    ) -> some View {
        if condition {
            self.popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }
}
