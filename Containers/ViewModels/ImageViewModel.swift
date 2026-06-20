//
//  ImageViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import Foundation

/// Represents the type of container volume
enum VolumeType: String, CaseIterable, Identifiable {
    /// Named volume with persistent identifier
    case named = "Named"

    /// Anonymous volume created automatically
    case anonymous = "Anonymous"

    var id: String { rawValue }
}

struct ImageViewModel: Identifiable, Hashable, Equatable {
    var name: String
    var tag: String
    var indexDigest: String
    var os: String
    var arch: String
    var variant: String
    var sizeInBytes: Int64
    var createdDate: Date
    var manifestDigest: String
    var inUse: Bool
    var imageDescription: ImageDescription

    var id: String {
        return indexDigest + manifestDigest + createdDate.description
    }

    init(_ item: ImageListItem) {
        self.init(
            item.description,
            variant: item.info?.variant,
            created: item.info?.created,
            os: item.info?.os,
            architecture: item.info?.architecture,
            inUse: item.inUse,
            sizeInBytes: item.info?.size
        )
    }

    /// Initialize from ImageDescription (simplified, without full image details)
    init(
        _ description: ImageDescription,
        variant: String? = nil,
        created: Date? = nil,
        os: String? = nil,
        architecture: String? = nil,
        inUse: Bool,
        sizeInBytes: Int64? = nil
    ) {
        self.imageDescription = description

        // Parse reference to get name and tag
        if let reference = try? ContainerizationOCI.Reference.parse(
            description.reference
        ) {
            self.name = reference.name
            self.tag = reference.tag ?? "<none>"
        } else {
            self.name = description.reference
            self.tag = "<none>"
        }

        self.indexDigest = description.digest
        self.manifestDigest = description.digest
        self.os = os ?? Platform.current.os
        self.arch = architecture ?? Platform.current.architecture
        self.variant = variant ?? ""
        self.sizeInBytes = sizeInBytes ?? description.descriptor.size
        self.createdDate = created ?? ImageInfo.unknownCreationDate
        self.inUse = inUse
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(indexDigest)
        hasher.combine(manifestDigest)
    }

    // Equatable conformance
    static func == (lhs: ImageViewModel, rhs: ImageViewModel) -> Bool {
        return lhs.indexDigest == rhs.indexDigest
            && lhs.manifestDigest == rhs.manifestDigest
    }
}

// MARK: - Display Formatting

extension ImageViewModel {
    var formattedDigest: String {
        String(digestWithoutAlgorithm.prefix(12))
    }

    var fullDigestWithoutAlgorithm: String {
        digestWithoutAlgorithm
    }

    private var digestWithoutAlgorithm: String {
        var d = indexDigest
        if d.hasPrefix("sha256:") {
            d = String(d.dropFirst("sha256:".count))
        }
        return d
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var formattedOS: String {
        os.localizedCapitalized
    }

    var formattedCreated: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdDate)
    }
}
