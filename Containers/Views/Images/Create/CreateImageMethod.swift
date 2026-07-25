//
//  CreateImageMethodStep.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI

struct CreateImageMethod: View {
    @Binding var selectedMethod: CreateImageView.CreationMethod?

    let onSelection: (CreateImageView.CreationMethod) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 68, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text("Create an Image")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 15) {
                Text("Choose how you want to add an image to your library.")
                    .fontWeight(.bold)

                Picker("", selection: $selectedMethod) {
                    ForEach(CreateImageView.CreationMethod.allCases, id: \.self) { method in
                        Text(method.rawValue)
                            .font(.body)
                            .tag(method as CreateImageView.CreationMethod?)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedMethod) { _, newValue in
                    if let method = newValue {
                        onSelection(method)
                    }

                }
            }
        }
        .frame(width: 460, alignment: .center)
    }
}
#Preview {
    @Previewable @State var selectedMethod: CreateImageView.CreationMethod? =
        .pull

    CreateImageMethod(selectedMethod: $selectedMethod) { method in
        selectedMethod = method
    }
    .padding()
}
