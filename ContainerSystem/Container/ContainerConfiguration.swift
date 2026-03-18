//
//  ContainerConfiguration.swift
//  Containers
//
//  Local implementation of ContainerConfiguration (replaces ContainerResource.ContainerConfiguration)
//

import Foundation
import ContainerizationOCI

/// Configuration for a container instance.
public struct ContainerConfiguration: Sendable, Codable {
    
    /// DNS resolver configuration.
    public struct DNSConfiguration: Sendable, Codable {
        public var nameservers: [String]
        public var domain: String?
        public var searchDomains: [String]
        public var options: [String]
        
        public static let defaultNameservers = ["1.1.1.1"]
        
        public init(
            nameservers: [String] = defaultNameservers,
            domain: String? = nil,
            searchDomains: [String] = [],
            options: [String] = []
        ) {
            self.nameservers = nameservers
            self.domain = domain
            self.searchDomains = searchDomains
            self.options = options
        }
    }
    
    /// Resource limits for the container.
    public struct Resources: Sendable, Codable {
        public var cpus: Int
        public var memoryInBytes: UInt64
        public var storage: UInt64?
        
        public init(cpus: Int = 2, memoryInBytes: UInt64 = 2 * 1024 * 1024 * 1024, storage: UInt64? = nil) {
            self.cpus = cpus
            self.memoryInBytes = memoryInBytes
            self.storage = storage
        }
    }
    
    public var id: String
    public var image: ImageDescription
    public var mounts: [Filesystem] = []
    public var publishedPorts: [PublishPort] = []
    public var publishedSockets: [PublishSocket] = []
    public var labels: [String: String] = [:]
    public var sysctls: [String: String] = [:]
    public var networks: [AttachmentConfiguration] = []
    public var dns: DNSConfiguration?
    public var rosetta: Bool = false
    public var initProcess: ProcessConfiguration
    public var platform: Platform = .current
    public var resources: Resources = Resources()
    public var virtualization: Bool = false
    public var ssh: Bool = false
    
    public init(id: String, image: ImageDescription, process: ProcessConfiguration) {
        self.id = id
        self.image = image
        self.initProcess = process
    }
}
