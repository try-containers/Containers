//
//  ImageHistory.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/12.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import SwiftUI

struct ImageHistory: View {
    let imageReference: String
    let platform: Platform

    @Environment(ImageManager.self) private var imageManager

    @SwiftUI.State private var layers: [LayerInfo] = []
    @SwiftUI.State private var isLoading = true
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError = false

    struct LayerInfo: Identifiable {
        let id = UUID()
        let digest: String?
        let size: Int64
        let command: String?
        let comment: String?
        let emptyLayer: Bool

        var formattedDigest: String {
            guard var d = digest else {
                return "<missing>"
            }
            if d.hasPrefix("sha256:") {
                d = String(d.dropFirst("sha256:".count))
            }
            if d.count > 12 {
                return String(d.prefix(12))
            }
            return d
        }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading image layers...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No layers found")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Unable to retrieve layer information for this image")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(layers.enumerated()), id: \.element.id) {
                            index,
                            layer in
                            layerRow(layer: layer, index: index)
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 500)
            }
        }
        .task {
            await loadLayers()
        }
        .alert(
            "Error",
            isPresented: $showError,
            actions: {
                Button("OK") {
                    self.showError = false
                }
            },
            message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
        )
    }

    private func layerRow(layer: LayerInfo, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Layer number badge
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let command = layer.command, !command.isEmpty {
                            Text(command)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        } else if layer.emptyLayer {
                            Text("Metadata step")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(layer.formattedDigest)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Text(layer.formattedSize)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let comment = layer.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadLayers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let layerInfo = try await imageManager.getImageLayers(
                imageReference: imageReference,
                platform: platform
            )

            // Convert ImageLayerDetail to LayerInfo
            self.layers = layerInfo.map { detail in
                LayerInfo(
                    digest: detail.digest,
                    size: detail.size,
                    command: detail.createdBy,
                    comment: detail.comment,
                    emptyLayer: detail.emptyLayer
                )
            }

        } catch {
            self.error = error
            self.showError = true
            self.layers = []
        }
    }
}
