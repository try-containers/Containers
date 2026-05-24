//
//  InfoSection.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 12)
            
            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.quinary)
            }
        }
    }
}
