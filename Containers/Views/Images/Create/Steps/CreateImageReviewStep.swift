//
//  CreateImageReviewStep.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import SwiftUI

struct CreateImageReviewStep: View {
    let selectedMethod: CreateImageWizard.CreationMethod?
    let imageName: String
    let tag: String
    let pullPlatform: PlatformSelection
    let dockerFile: URL?
    let contextDirectory: URL?
    let buildTag: String
    let buildPlatform: PlatformSelection
    let targetStage: String
    let tarFile: URL?

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Text("Review your configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                reviewItem(
                    title: "Method",
                    value: selectedMethod?.rawValue ?? "None"
                )

                switch selectedMethod {
                case .pull:
                    reviewItem(title: "Image", value: "\(imageName):\(tag)")
                    reviewItem(title: "Platform", value: pullPlatform.description)

                case .build:
                    reviewItem(
                        title: "Dockerfile",
                        value: dockerFile?.path ?? "Not set"
                    )
                    reviewItem(
                        title: "Build Directory",
                        value: contextDirectory?.path ?? "Not set"
                    )
                    reviewItem(
                        title: "Image Name",
                        value: buildTag.isEmpty
                            ? "Auto-generated UUID" : buildTag
                    )
                    reviewItem(title: "Platform", value: buildPlatform.description)
                    if !targetStage.isEmpty {
                        reviewItem(title: "Target Stage", value: targetStage)
                    }

                case .load:
                    reviewItem(
                        title: "Tar File",
                        value: tarFile?.lastPathComponent ?? "Not set"
                    )

                case .none:
                    EmptyView()
                }
            }
            .frame(width: 360, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func reviewItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
