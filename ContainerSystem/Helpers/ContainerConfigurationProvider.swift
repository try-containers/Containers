//
//  ContainerConfigurationProvider.swift
//  Containers
//
//  Protocol for types that provide container configuration

//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Containerization
import ContainerizationOCI
import ContainerSystem

/// Protocol for types that provide access to container configuration
protocol ContainerConfigurationProvider {
    var configuration: ContainerConfiguration { get }
}

extension ContainerConfigurationProvider {
    
    var imageName: String {
        return self.configuration.image.reference
    }
    
    var portsString: String? {
        if self.configuration.publishedPorts.isEmpty {
            return nil
        }
        
        return self.configuration.publishedPorts.map(\.description).joined(separator: "\n")
    }
    
    var volumeFSs: [Filesystem] {
        let fileSystems = self.configuration.mounts
        let volumes = fileSystems.filter({ $0.isVolume })
        
        return volumes
    }
    
    var volumeNames: [String] {
        let volumeNames = self.volumeFSs.map(\.volumeName).filter({$0 != nil}).map({$0!})
        
        return volumeNames
    }
}
