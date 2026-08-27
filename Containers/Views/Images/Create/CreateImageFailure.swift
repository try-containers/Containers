//
//  CreateImageFailure.swift
//  Containers
//
//  Created by Axel Martinez on 24/08/2026.
//

import SwiftUI

/// What the assistant shows in place of its own content once the work it was
/// there to do has failed: what happened, said plainly, with the registry's
/// own account of it kept a click away.
struct CreateImageFailure: View {
    let failure: ErrorAlert

    @State private var showsDetails: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Text(failure.title)
                .font(.headline)

            // A registry or a build can answer at length, so the message
            // scrolls rather than growing the pane past the sheet.
            ScrollView {
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 140)

            if let details = failure.details {
                DisclosureGroup(isExpanded: $showsDetails) {
                    ScrollView {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 110)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    )
                } label: {
                    Text(showsDetails ? "Hide Details" : "Show Details")
                        .font(.subheadline)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
