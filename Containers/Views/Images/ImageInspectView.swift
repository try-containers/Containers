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
                    InfoSection(title: "Image", subtitle: nil) {
                        InfoRow(label: "Reference", value: image.imageDescription.reference)
                        InfoRow(label: "Tag", value: image.tag)
                    }
                    
                    // Platform
                    InfoSection(title: "Platform", subtitle: nil) {
                        InfoRow(label: "OS", value: image.formattedOS)
                        InfoRow(label: "Architecture", value: image.formattedArch)
                        
                        if !image.variant.isEmpty {
                            InfoRow(label: "Variant", value: image.variant)
                        }
                    }
                    
                    // Size Information
                    InfoSection(title: "Size", subtitle: nil) {
                        InfoRow(label: "Total Size", value: image.formattedSize)
                        InfoRow(label: "Descriptor Size", value: ByteCountFormatter.string(fromByteCount: image.imageDescription.descriptor.size, countStyle: .file))
                    }
                    
                    // Descriptor Details
                    InfoSection(title: "Descriptor", subtitle: nil){
                        InfoRow(label: "Media Type", value: image.imageDescription.descriptor.mediaType)
                    }
                    
                    // Created Date
                    InfoSection(title: "Metadata", subtitle: nil) {
                        InfoRow(label: "Created", value: image.formattedCreated)
                    }
                    
                    // Usage Information
                    InfoSection(title: "Usage", subtitle: nil){
                        if image.inUse {
                            InfoRow(label: "In Use", value: "Yes")
                            InfoRow(label: "Containers", value: "\(image.inUseContainers.count)")
                        } else {
                            InfoRow(label: "In Use", value: "No")
                        }
                    }
                    
                }
            )
            .padding(20)
        }
    }
  
}
