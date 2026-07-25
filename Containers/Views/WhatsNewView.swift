//
//  WhatsNewView.swift
//  Containers
//
//  Created by Axel Martinez on 22/07/2026.
//

import AppKit
import SwiftUI

struct WhatsNewView: View {
    let isFirstLaunch: Bool
    let onContinue: () -> Void

    private struct Feature {
        let icon: String
        let color: Color
        let title: String
        let description: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "cube.transparent.fill",
            color: .blue,
            title: "Container Management",
            description:
                "Create, run, and monitor Linux containers natively on Apple Silicon."
        ),
        Feature(
            icon: "shippingbox.circle.fill",
            color: .orange,
            title: "Image Library",
            description:
                "Pull from registries, build from Dockerfiles, or load from tar archives."
        ),
        Feature(
            icon: "internaldrive.fill",
            color: .purple,
            title: "Volumes & Mounts",
            description:
                "Attach persistent volumes and share host directories with your containers."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(isFirstLaunch ? "Welcome to" : "What's New in")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Containers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(features, id: \.title) { feature in
                        featureRow(feature)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
        }
        .padding(36)
        .frame(width: 500, height: 460)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 28))
                .foregroundStyle(feature.color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("First Launch") {
    WhatsNewView(isFirstLaunch: true, onContinue: {})
}

#Preview("Update") {
    WhatsNewView(isFirstLaunch: false, onContinue: {})
}
