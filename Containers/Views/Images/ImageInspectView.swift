//
//  ImageInspectView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/14.
//

import SwiftUI
import AppKit
import Containerization
import ContainerSystem

import ContainerizationOCI

struct ImageInspectView: View {
    let image: ImageViewModel
    
    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20,
                content: {
                    // Image Information
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Image", subtitle: nil)
                        
                        infoRow(label: "Reference", value: image.imageDescription.reference)
                        infoRow(label: "Tag", value: image.tag)
                        
                    }

                    // Platform
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Platform", subtitle: nil)
                        
                        infoRow(label: "OS", value: image.formattedOS)
                        infoRow(label: "Architecture", value: image.formattedArch)
                        if !image.variant.isEmpty {
                            infoRow(label: "Variant", value: image.variant)
                        }
                    }
                    
                    // Size Information
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Size", subtitle: nil)
                        
                        infoRow(label: "Total Size", value: image.formattedSize)
                        infoRow(label: "Descriptor Size", value: ByteCountFormatter.string(fromByteCount: image.imageDescription.descriptor.size, countStyle: .file))
                    }
                    
                    // Descriptor Details
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Descriptor", subtitle: nil)
                        
                        infoRow(label: "Media Type", value: image.imageDescription.descriptor.mediaType)
                    }
                    
                    // Created Date
                    
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Metadata", subtitle: nil)
                        
                        infoRow(label: "Created", value: image.formattedCreated)
                    }
                    
                    
                    // Usage Information
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Usage", subtitle: nil)
                        
                        if image.inUse {
                            infoRow(label: "In Use", value: "Yes")
                            infoRow(label: "Containers", value: "\(image.inUseContainers.count)")
                        } else {
                            infoRow(label: "In Use", value: "No")
                        }
                    }
                }
            )
            .padding(20)
        }
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
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
