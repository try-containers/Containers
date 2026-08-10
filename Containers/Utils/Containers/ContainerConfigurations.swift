//
//  ContainerConfigurations.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

struct PortsConfiguration: Identifiable {
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

struct VolumeMountConfiguration: Identifiable {
    enum Source: String, CaseIterable, Hashable, CustomStringConvertible {
        case volume = "Volume"
        case anonymousVolume = "Anonymous Volume"

        var description: String { rawValue }
    }

    let id: UUID = UUID()
    var source: Source = .volume
    var volumeName: String = ""
    var target: String = ""

    var summary: String {
        trimmedTarget.isEmpty
            ? sourceLabel : "\(sourceLabel) -> \(trimmedTarget)"
    }

    var columns: [String] {
        [sourceLabel, trimmedTarget]
    }

    var sourceLabel: String {
        switch source {
        case .volume:
            trimmedVolumeName.isEmpty ? "No Volume" : trimmedVolumeName
        case .anonymousVolume:
            "Anonymous Volume"
        }
    }

    var trimmedVolumeName: String {
        volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTarget: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MountConfiguration: Identifiable {
    let id: UUID = UUID()
    var hostPath: String = ""
    var containerPath: String = ""

    var summary: String {
        if trimmedSource.isEmpty && trimmedTarget.isEmpty {
            return "New Mount"
        }

        if trimmedSource.isEmpty {
            return trimmedTarget.isEmpty
                ? "Temporary Mount" : "Temporary Mount -> \(trimmedTarget)"
        }

        return trimmedTarget.isEmpty
            ? trimmedSource : "\(trimmedSource) -> \(trimmedTarget)"
    }

    var columns: [String] {
        [
            trimmedSource.isEmpty ? "Temporary Mount" : trimmedSource,
            trimmedTarget,
        ]
    }

    var trimmedSource: String {
        hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTarget: String {
        containerPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CapabilityConfiguration: Identifiable {
    let id: UUID = UUID()
    var name: String = ""

    var summary: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension [CapabilityConfiguration] {
    var names: [String] {
        map(\.summary).filter { !$0.isEmpty }
    }
}
