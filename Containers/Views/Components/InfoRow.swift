//
//  InfoRow.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
