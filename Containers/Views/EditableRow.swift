//
//  EditableRow.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI

struct EditableRow<Content: View>: View {
    @ViewBuilder var content: Content

    var onAdd: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            content
            
            Spacer()
                .frame(width: 8)
            
            HStack(spacing: 4) {
                Button(action: {
                    self.onAdd()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Add new row")
                
                Button(action: {
                    self.onDelete()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Delete this row")
            }
            .fixedSize()
        }
    }
}
