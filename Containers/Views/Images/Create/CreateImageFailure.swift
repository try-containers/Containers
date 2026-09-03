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
    /// How far the message runs before it starts scrolling instead of growing.
    private static let maximumMessageHeight: CGFloat = 140

    /// How wide the writing under the mark runs before it wraps.
    private static let writingWidth: CGFloat = 420

    let failure: ErrorAlert

    @State private var showsDetails: Bool = false
    @State private var messageHeight: CGFloat = 0

    /// The mark sits on the sheet's centre line, where the progress spinner
    /// stood, and the account of what went wrong hangs under it as an overlay:
    /// an overlay takes no part in laying out what it is attached to, so a
    /// long message runs downwards instead of carrying the mark up.
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 38))
            .foregroundStyle(.secondary)
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    Text(failure.title)
                        .font(.headline)

                    // A registry or a build can answer at length, so a message
                    // past the limit scrolls; a shorter one is given only the
                    // height it needs. The height is measured and set exactly,
                    // because both a scroll view and a `maxHeight` frame take
                    // all the room they are offered, and the empty space under
                    // a single line would leave the message floating away from
                    // the title above it.
                    ScrollView {
                        message
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                messageHeight = $0
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(messageHeight, Self.maximumMessageHeight))

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
                .frame(width: Self.writingWidth)
                // Hung from the mark's foot rather than sharing its bottom
                // edge, which is what puts the writing below it.
                .alignmentGuide(VerticalAlignment.bottom) { _ in
                    -CGFloat.sheetMarkSpacing
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: some View {
        Text(failure.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
    }
}
