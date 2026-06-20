//
//  VolumeViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Foundation

@dynamicMemberLookup
struct VolumeViewModel: Identifiable, Hashable, Equatable {
    var volume: Volume
    var inUse: Bool

    var volumeType: VolumeType {
        self.volume.isAnonymous ? .anonymous : .named
    }

    var labels: [String: String] {
        self.volume.labels.filter({ $0.key != Volume.anonymousLabel })
    }

    var options: [String: String] {
        self.volume.options.filter({ $0.key != "KB" })
    }

    var id: String {
        return volume.id
    }

    init(_ item: VolumeListItem) {
        self.volume = item.volume
        self.inUse = item.inUse
    }

    init(_ volume: Volume, inUse: Bool = false) {
        self.volume = volume
        self.inUse = inUse
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(volume.id)
        hasher.combine(volume.name)
        hasher.combine(inUse)
    }

    // Equatable conformance
    static func == (lhs: VolumeViewModel, rhs: VolumeViewModel) -> Bool {
        return lhs.volume.id == rhs.volume.id
            && lhs.volume.name == rhs.volume.name && lhs.inUse == rhs.inUse
    }

}

extension VolumeViewModel {
    subscript<T>(dynamicMember keyPath: KeyPath<Volume, T>) -> T {
        return volume[keyPath: keyPath]
    }
}

// MARK: - Display Formatting

extension VolumeViewModel {
    var formattedCreated: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: volume.createdAt)
    }

    var formattedSize: String? {
        guard let volumeSize = volume.sizeInBytes else {
            return nil
        }

        let formattedSize = ByteCountFormatter.string(
            fromByteCount: Int64(volumeSize),
            countStyle: .file
        )

        return formattedSize
    }
}
