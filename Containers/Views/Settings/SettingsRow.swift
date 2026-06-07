//
//  SettingsRow.swift
//  Containers
//
//  Created by Axel Martinez on 06/06/2026.
//

import SwiftUI

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 116, alignment: .trailing)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
