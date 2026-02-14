//
//  ImageHistoryView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/12.
//

import SwiftUI
import ContainerSystem
import ContainerResource
import ContainerizationOCI

struct ImageHistoryView: View {
    let imageReference: String
    let platform: Platform
    
    @Environment(ImageManager.self) private var imageManager
    
    @SwiftUI.State private var layers: [LayerInfo] = []
    @SwiftUI.State private var isLoading = true
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError = false
    
    struct LayerInfo: Identifiable {
        let id = UUID()
        let digest: String
        let size: Int64
        let command: String?
        let comment: String?
        
        var formattedDigest: String {
            var d = digest
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
                emptyStateView
            } else {
                layersListView
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
    
    private var emptyStateView: some View {
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
    }
    
    private var layersListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                sectionHeader(
                    title: "Layer History",
                    subtitle: "\(layers.count) layer\(layers.count == 1 ? "" : "s")"
                )
                
                // Total size
                let totalSize = layers.reduce(0) { $0 + $1.size }
                
                HStack {
                    Label("Total Size", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Layers list
                VStack(spacing: 8) {
                    ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                        layerRow(layer: layer, index: index)
                    }
                }
            }
            .padding(20)
        }
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
    
    @MainActor
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
                    comment: detail.comment
                )
            }
            
        } catch {
            self.error = error
            self.showError = true
            self.layers = []
        }
    }
}
