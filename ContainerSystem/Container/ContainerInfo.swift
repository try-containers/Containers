//
//  ContainerInfo.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import ContainerizationOCI

public struct ContainerInfo: Sendable {
    public var virtualFileSystem: [Filesystem] = []
    public var volumes: [Filesystem] = []
    public var publishPorts: [PublishPort] = []
    public var publishSockets: [PublishSocket] = []
    public var temporaryFileSystem: [Filesystem] = []
    public var entryPoint: String?
    public var platform: String?
    public var os = "linux"
    public var arch: String = Platform.current.architecture
    public var kernel: String?
    public var networks: [String] = []
    public var cidfile = ""
    public var labels: [String: String] = [:]
    
    // PRAGMA: DNS
    
    public var dnsDisabled = false
    public var dnsNameservers: [String] = []
    public var dnsDomain: String? = nil
    public var dnsSearchDomains: [String] = []
    public var dnsOptions: [String] = []
    
    // PRAGMA: FLAGS
    public var deleteOnTermination = false
    public var virtualization: Bool = false
    public var ssh = false
    
    public init() {}
}
