//
//  InfoSection.swift
//  Containers
//
//  Created by Axel Martinez on 20/5/26.
//

import SwiftUI

struct InfoSection: View {
    let title: String?
    let subtitle: String?
    let emptyImage: String?
    let emptyMessage: String?
    let rows: [InfoRow]
    
    init(
        title: String? = nil,
        subtitle: String? = nil,
        emptyImage: String? = nil,
        emptyMessage: String? = nil,
        rows: [InfoRow]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.emptyImage = emptyImage
        self.emptyMessage = emptyMessage
        self.rows = rows
    }
    
    var body: some View {
        GroupBox(content: {
            if rows.isEmpty {
                Group {
                    if let emptyImage {
                        Image(systemName: emptyImage)
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let emptyMessage {
                        Text(emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index != 0 {
                        Divider()
                            .padding(.horizontal, 12)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    
                    row
                }
            }
        }, label: {
            Group {
                if let title {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 5)
        })
        
    }
}

#Preview {
    InfoSection(title: "Test Section", subtitle: "Test subtitle", rows: [
        InfoRow(label: "Test title", value: "Test vaue"),
        InfoRow(label: "Test title 2", value: "Test value 2")
    ])
}
