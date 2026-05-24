//
//  DNSManager.swift
//  Containers
//
//  Manager for DNS resolver configuration
//  Architecture: Utility manager for DNS resolver files
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import Observation
import Logging

/// Manages DNS resolver configuration for container domains.
/// Create instances via public init() - stateless utility manager.
@Observable
@MainActor
public final class NetworkManager {

    private static let resolverDirectory = "/etc/resolver"
    private static let filePrefix = "containerization."
    private static let nameserver = "127.0.0.1"
    private static let port = "2053"
    
    private let logger: Logger
    
    /// Public initializer - creates instance
    public init() {
        var logger = Logger(label: "app.containers.manager.dns")
        logger.logLevel = .debug
        self.logger = logger
    }
    
    // MARK: - Public API
    
    public func listDomains() -> [String] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: Self.resolverDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasPrefix(Self.filePrefix) }
            .map { String($0.dropFirst(Self.filePrefix.count)) }
            .sorted()
    }

    // MARK: - Create domain

    public func createDomain(name: String) throws {
        // DNS domain creation requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns create <domain>
        throw DNSError.notSupported
    }

    // MARK: - Delete domain

    public func deleteDomain(name: String) throws {
        // DNS domain deletion requires root privileges.
        // This functionality is disabled in the GUI.
        // Use the CLI with sudo: sudo container system dns delete <domain>
        throw DNSError.notSupported
    }

    // MARK: - Errors

    public enum DNSError: LocalizedError {
        case invalidDomainName
        case notSupported

        public var errorDescription: String? {
            switch self {
            case .invalidDomainName:
                return "Domain name cannot be empty."
            case .notSupported:
                return """
                DNS domain management requires administrator privileges and is not available in the GUI. 
                You can manually create resolver files in /etc/resolver/ if needed.
                """
            }
        }
    }
}
