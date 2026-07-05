//
//  CreateImageMethodStep.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI

struct CreateImageMethodStep: View {
    @Binding var selectedMethod: CreateImageWizard.CreationMethod?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(CreateImageWizard.CreationMethod.allCases, id: \.self) {
                method in
                Button {
                    selectedMethod = method
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: method.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(
                                selectedMethod == method
                                    ? .blue : .secondary
                            )
                            .frame(width: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(method.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(method.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedMethod == method {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 24))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                selectedMethod == method
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedMethod == method
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.3),
                                lineWidth: 2
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
