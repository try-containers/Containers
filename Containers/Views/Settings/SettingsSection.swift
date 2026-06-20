//
//  SettingsSection.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import SwiftUI

struct SettingsSection<Label: View, Option: Hashable & CustomStringConvertible, Format: ParseableFormatStyle>: View
    where Format.FormatOutput == String {

    typealias Field = SettingsField<Label, Option, Format>

    let title: String?
    let description: String?
    let fields: [Field]

    init(
        title: String? = nil,
        description: String? = nil,
        fields: [Field]
    ) {
        self.title = title
        self.description = description
        self.fields = fields
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(fields.indices, id: \.self) { index in
                    fields[index]

                    if index < fields.index(before: fields.endIndex) {
                        Divider()
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(12)
        } label: {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 5)
            }
        }
    }
}
