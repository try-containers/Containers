//
//  PortMapping.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

struct PortMapping: Identifiable {
    let id: UUID = UUID()
    var hostAddress: String = "127.0.0.1"
    var host: Int = 0
    var container: Int = 0
    var publishProtocol: PublishProtocol = .tcp

    var publishedPort: PublishPort {
        let address = try? IPAddress(
            hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard let fallbackAddress = try? IPAddress("127.0.0.1") else {
            fatalError("Invalid fallback IP Addres")
        }

        return .init(
            hostAddress: address ?? fallbackAddress,
            hostPort: UInt16(self.host),
            containerPort: UInt16(self.container),
            proto: self.publishProtocol,
            count: 1
        )
    }

    var summary: String {
        "\(hostAddress):\(host):\(container)/\(publishProtocol.rawValue.uppercased())"
    }

    var columns: [String] {
        [
            "\(hostAddress):\(host)",
            "\(container)",
            publishProtocol.rawValue.uppercased(),
        ]
    }
}
