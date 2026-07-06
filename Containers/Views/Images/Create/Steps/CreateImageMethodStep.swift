//
//  CreateImageMethodStep.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI

struct CreateImageMethodStep: View {
    @Binding var selectedMethod: CreateImageView.CreationMethod?

    let onSelection: (CreateImageView.CreationMethod) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shippingbox.circle")
                .font(.system(size: 68, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Create an Image")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Choose how you want to add an image to your library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(CreateImageView.CreationMethod.allCases, id: \.self) { method in
                    methodRow(method)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 460, alignment: .center)
    }

    private func methodRow(_ method: CreateImageView.CreationMethod) -> some View {
        Button {
            onSelection(method)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: selectedMethod == method
                        ? "largecircle.fill.circle" : "circle"
                )
                .font(.system(size: 13))
                .foregroundStyle(
                    selectedMethod == method ? Color.accentColor : .secondary
                )
                .frame(width: 18, height: 18)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(method.rawValue)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(method.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 300, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
