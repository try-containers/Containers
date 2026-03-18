//
//  PublishPort.swift
//  Containers
//
//  Local implementation of PublishPort (replaces ContainerResource.PublishPort)
//

import Foundation
import ContainerizationExtras

/// Network protocol for published ports.
public enum PublishProtocol: String, Sendable, Codable, CaseIterable {
    case tcp
    case udp
    
    public init() {
        self = .tcp
    }
    
    public init(_ value: String) {
        switch value.lowercased() {
        case "udp":
            self = .udp
        default:
            self = .tcp
        }
    }
}

/// Represents a port forwarding rule from host to container.
public struct PublishPort: Sendable, Codable {
    public var hostAddress: IPAddress
    public var hostPort: UInt16
    public var containerPort: UInt16
    public var proto: PublishProtocol
    public var count: UInt16
    
    public init(
        hostAddress: IPAddress = try! IPAddress("127.0.0.1"),
        hostPort: UInt16,
        containerPort: UInt16,
        proto: PublishProtocol = .tcp,
        count: UInt16 = 1
    ) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.proto = proto
        self.count = count
    }
}

extension PublishPort: CustomStringConvertible {
    public var description: String {
        "\(self.hostPort):\(self.containerPort) (\(self.proto.rawValue.localizedUppercase))"
    }
}

extension Array where Element == PublishPort {
    /// Check for overlapping port configurations.
    public func hasOverlaps() -> Bool {
        var seen = Set<String>()
        for port in self {
            for i in 0..<port.count {
                let key = "\(port.hostAddress):\(port.hostPort + i)/\(port.proto.rawValue)"
                if seen.contains(key) {
                    return true
                }
                seen.insert(key)
            }
        }
        return false
    }
}
