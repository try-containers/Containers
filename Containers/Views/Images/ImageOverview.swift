//
//  ImageOverview.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import SwiftUI

struct ImageOverview: View {
    let image: ImageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(rows: detailRows)

            }
            .padding(20)
        }
    }

    private var detailRows: [InfoRow] {
        [
            InfoRow(label: "Tag", value: image.tag),
            InfoRow(label: "Digest", value: image.fullDigestWithoutAlgorithm),
            InfoRow(label: "Size", value: image.formattedSize),
            InfoRow(label: "Created", value: image.formattedCreated)
        ]
    }
}
