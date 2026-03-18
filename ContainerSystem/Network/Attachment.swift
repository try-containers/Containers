//
//  Attachment.swift
//  Containers
//
//  Local implementation of network attachment types (replaces ContainerResource network types)
//

import Foundation
import ContainerizationExtras

/// Represents a network attachment for a running container.
public struct Attachment: Sendable, Codable {
    public var network: String
    public var hostname: String
    public var ipv4Address: CIDRv4
    public var ipv4Gateway: IPv4Address
    public var ipv6Address: CIDRv6?
    public var macAddress: MACAddress?
    
    public init(
        network: String,
        hostname: String,
        ipv4Address: CIDRv4,
        ipv4Gateway: IPv4Address,
        ipv6Address: CIDRv6? = nil,
        macAddress: MACAddress? = nil
    ) {
        self.network = network
        self.hostname = hostname
        self.ipv4Address = ipv4Address
        self.ipv4Gateway = ipv4Gateway
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
    }
}

/// Configuration for attaching a container to a network.
public struct AttachmentConfiguration: Sendable, Codable {
    public var network: String
    public var options: AttachmentOptions
    
    public init(network: String, options: AttachmentOptions = AttachmentOptions()) {
        self.network = network
        self.options = options
    }
}

/// Options for a network attachment.
public struct AttachmentOptions: Sendable, Codable {
    public var hostname: String
    
    public init(hostname: String = "") {
        self.hostname = hostname
    }
}
