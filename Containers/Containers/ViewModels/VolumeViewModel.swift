//
//  VolumeViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation
import ContainerResource

@dynamicMemberLookup
struct VolumeViewModel: Identifiable {
    var volume: Volume
    var inUseContainers: [ContainerSnapshot]
    
    var inUse: Bool {
        return !inUseContainers.isEmpty
    }
    
    var volumeType: VolumeType {
        self.volume.isAnonymous ? .anonymous : .named
    }
    
    var labels: [String : String] {
        self.volume.labels.filter({$0.key != Volume.anonymousLabel})
    }
    
    var options: [String : String] {
        self.volume.options.filter({$0.key != "KB"})
    }

    var id: String {
        return volume.id
    }
    
    init(_ volume: Volume, containers: [ContainerSnapshot]) {
        self.volume = volume
        self.inUseContainers = containers.filter({ container in
            container.volumeNames.contains(volume.name)
        })
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
        
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(volumeSize), countStyle: .file)
        
        return formattedSize
    }
}
