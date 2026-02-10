//
//  ImageViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation
import ContainerAPIService
import ContainerizationOCI
import ContainerResource

/// Represents the type of container volume
enum VolumeType: String, CaseIterable, Identifiable {
    /// Named volume with persistent identifier
    case named = "Named"

    /// Anonymous volume created automatically
    case anonymous = "Anonymous"

    var id: String { rawValue }
}

struct ImageViewModel: Identifiable {
    var name: String
    var tag: String
    var indexDigest: String
    var rawOS: String
    var rawArch: String
    var variant: String
    var sizeInBytes: Int64
    var createdDate: Date?
    var manifestDigest: String
    var inUseContainers: [ContainerSnapshot]
    var imageDescription: ImageDescription

    var inUse: Bool {
        return !inUseContainers.isEmpty
    }
    
    var id: String {
        return indexDigest + manifestDigest + (createdDate?.description ?? "")
    }
    
    /// Initialize from ImageDescription (simplified, without full image details)
    init(_ description: ImageDescription, containers: [ContainerSnapshot]) {
        self.imageDescription = description
        
        // Parse reference to get name and tag
        if let reference = try? ContainerizationOCI.Reference.parse(description.reference) {
            self.name = reference.name
            self.tag = reference.tag ?? "<none>"
        } else {
            self.name = description.reference
            self.tag = "<none>"
        }
        
        self.indexDigest = description.digest
        self.manifestDigest = description.digest
        self.rawOS = "Linux"
        self.rawArch = Platform.current.architecture
        self.variant = ""
        self.sizeInBytes = description.descriptor.size
        self.createdDate = nil
        
        self.inUseContainers = containers.filter { $0.configuration.image.digest == description.digest }
    }
}

// MARK: - Display Formatting

extension ImageViewModel {
    var formattedDigest: String {
        var d = indexDigest
        if d.hasPrefix("sha256:") {
            d = String(d.dropFirst("sha256:".count))
        }
        if d.count > 24 {
            return String(d.prefix(24)) + "..."
        }
        return d
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
    
    var formattedOS: String {
        rawOS.localizedCapitalized
    }
    
    var formattedArch: String {
        rawArch.localizedCapitalized
    }
    
    var formattedCreated: String {
        guard let date = createdDate else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
