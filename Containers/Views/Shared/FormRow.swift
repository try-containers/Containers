//
//  FormRow.swift
//  Containers
//
//  Created by Axel Martinez on 09/08/2026.
//

import SwiftUI

/// A labelled row in a `FormStack`, with the control column's width and the
/// caption that can sit under it.
struct FormRow<Content: View>: View {
    var title: String?
    var description: String?
    @ViewBuilder var content: Content

    var body: some View {
        if let title {
            LabeledContent {
                column
            } label: {
                Text("\(title):")
            }
        } else {
            column
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 4) {
            content

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fieldControl()
    }
}
