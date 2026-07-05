//
//  ContainerConfigurationProvider.swift
//  Containers
//
//  Protocol for types that provide container configuration

//  Created by Axel Martinez on 2026/02/08.
//

import ContainerSystem
import Containerization
import ContainerizationOCI
import Foundation

/// Protocol for types that provide access to container configuration
protocol ContainerConfigurationProvider {
    var configuration: ContainerConfiguration { get }
}

extension ContainerConfigurationProvider {

    var imageName: String {
        self.configuration.image.reference
    }

    var portsString: String? {
        if self.configuration.publishedPorts.isEmpty {
            return nil
        }

        return self.configuration.publishedPorts.map(\.description).joined(
            separator: "\n"
        )
    }

    var volumeFSs: [Filesystem] {
        let fileSystems = self.configuration.mounts
        let volumes = fileSystems.filter({ $0.isVolume })

        return volumes
    }

    var volumeNames: [String] {
        let volumeNames = self.volumeFSs
            .compactMap(\.volumeName)
            .map({ $0 })

        return volumeNames
    }
}
