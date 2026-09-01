//
//  ContainerViewModel.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation

struct ContainerViewModel: Identifiable, Hashable, Equatable {
    var id: String
    var name: String { id }
    var imageName: String
    var status: ContainerStatus
    var ports: String
    var ipAddress: String?
    var os: String
    var arch: String
    var startedDate: Date?
    /// Whether the row is working, which is part of the row: a table only
    /// rebuilds a cell when the row it draws has changed.
    var isBusy: Bool = false

    init(_ snapshot: ContainerSnapshot) {
        self.id = snapshot.configuration.id
        self.imageName = snapshot.configuration.image.reference
        self.status = snapshot.status
        self.ports = snapshot.configuration.publishedPorts.map {
            "\($0.hostAddress):\($0.hostPort)\u{2192}\($0.containerPort)/\($0.proto.rawValue)"
        }.joined(separator: "\n")
        self.ipAddress = snapshot.networks.first.map { network in
            let addressString = network.ipv4Address.description
            return String(
                addressString.split(separator: "/").first
                    ?? Substring(addressString)
            )
        }
        self.os = snapshot.configuration.platform.os
        self.arch = snapshot.configuration.platform.architecture
        self.startedDate = snapshot.startedDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(status)
    }

    static func == (lhs: ContainerViewModel, rhs: ContainerViewModel) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
            && lhs.isBusy == rhs.isBusy
    }
}

// MARK: - Display Formatting

extension ContainerViewModel {
    var formattedPorts: String {
        ports.isEmpty ? "-" : ports
    }

    var hasIPAddress: Bool {
        ipAddress != nil
    }

    var formattedIPAddress: String {
        ipAddress ?? "-"
    }

    var formattedOS: String {
        os.localizedCapitalized
    }

    var formattedState: String {
        status.rawValue.localizedCapitalized
    }

    var formattedStarted: String {
        guard let startedDate else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: startedDate)
    }

    func formattedUptime(at date: Date = Date()) -> String {
        guard status == .running, let startedDate else {
            return "-"
        }

        let interval = max(0, date.timeIntervalSince(startedDate))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "-"
    }
}
