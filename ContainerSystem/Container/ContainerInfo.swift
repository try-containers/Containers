//
//  ContainerInfo.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/04.
//

import ContainerizationOCI
import Foundation

public struct ContainerInfo: Sendable {
    public var name = ""
    public var virtualFileSystem: [Filesystem] = []
    public var volumes: [Filesystem] = []
    public var publishPorts: [PublishPort] = []
    public var publishSockets: [PublishSocket] = []
    public var temporaryFileSystem: [Filesystem] = []
    public var entryPoint: String?
    public var platform: Platform?
    public var kernel: String?
    public var networks: [String] = []
    public var cidfile = ""
    public var labels: [String: String] = [:]
    public var capabilities: [String] = []
    public var shmSize: UInt64?
    public var stopSignal: String?

    // MARK: DNS

    public var dnsDisabled = false
    public var dnsNameservers: [String] = []
    public var dnsDomain: String? = nil
    public var dnsSearchDomains: [String] = []
    public var dnsOptions: [String] = []

    // MARK: FLAGS

    public var deleteOnTermination = false
    public var virtualization: Bool = false
    public var ssh = false

    public init() {}
}
