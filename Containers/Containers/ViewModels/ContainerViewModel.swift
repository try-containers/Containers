//
//  ContainerViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation
import ContainerizationOCI
import ContainerNetworkService
import ContainerResource
import ContainerizationExtras

struct ContainerViewModel: Identifiable {
    var id: String
    var image: ImageDescription
    var status: RuntimeStatus
    var snapshot: ContainerSnapshot

    var name: String {
        return self.id
    }
    
    var imageName: String {
        return self.image.reference
    }
    
    init(_ snapshot: ContainerSnapshot) {
        self.id = snapshot.configuration.id
        self.image = snapshot.configuration.image
        self.status = snapshot.status
        self.snapshot = snapshot
    }
}

// MARK: - Display Formatting

extension ContainerViewModel {
    var formattedPorts: String {
        let ports = snapshot.configuration.publishedPorts.map {
            "\($0.hostAddress):\($0.hostPort)\u{2192}\($0.containerPort)/\($0.proto.rawValue)"
        }.joined(separator: "\n")
        return ports.isEmpty ? "-" : ports
    }
    
    var hasIPAddress: Bool {
        return !snapshot.networks.isEmpty
    }
    
    var formattedIPAddress: String {
        if let network = snapshot.networks.first {
            let addressString = network.ipv4Address.description
            return String(addressString.split(separator: "/").first ?? Substring(addressString))
        } else {
            return "-"
        }
    }
    
    var formattedOS: String {
        snapshot.configuration.platform.os.localizedCapitalized
    }
    
    var formattedArch: String {
        snapshot.configuration.platform.architecture.localizedCapitalized
    }
    
    var formattedCPUs: String {
        "\(snapshot.configuration.resources.cpus)"
    }
    
    var formattedMemory: String {
        "\(snapshot.configuration.resources.memoryInBytes / (1024 * 1024)) MB"
    }
    
    var formattedState: String {
        status.rawValue.localizedCapitalized
    }
}
