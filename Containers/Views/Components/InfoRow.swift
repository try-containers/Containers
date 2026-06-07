//
//  InfoRow.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoRow: View {
    let icon: String?
    let label: String?
    let value: String
    let action: ActionButton?
    
    init(icon: String? = nil, label: String? = nil, value: String, action: ActionButton? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
        self.action = action
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if let icon, let label {
                Label(
                    label,
                    systemImage: icon
                )
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                
                Spacer()
            }  else if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 140, alignment: .leading)
                
                Spacer()
            } else if let label {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 140, alignment: .leading)
                
                Spacer()
            }
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
