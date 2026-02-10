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
public final class DNSManager {

    private static let resolverDirectory = "/etc/resolver"
    private static let filePrefix = "containerization."
    private static let nameserver = "127.0.0.1"
    private static let port = "2053"
    
    private let logger: Logger
    
    /// Public initializer - creates instance
    public init() {
        var logger = Logger(label: "app.containers.manager.dns")
        logger.logLevel = .info
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
        logger.info("Creating DNS domain: \(name)")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DNSError.invalidDomainName
        }

        let filePath = "\(Self.resolverDirectory)/\(Self.filePrefix)\(trimmed)"
        let fileContent = "nameserver \(Self.nameserver)\\nport \(Self.port)"

        let script = """
        do shell script "printf '\(fileContent)\\n' > \(filePath) && killall -HUP mDNSResponder" with administrator privileges
        """

        try Self.runAppleScript(script)
        logger.info("DNS domain created: \(name)")
    }

    // MARK: - Delete domain

    public func deleteDomain(name: String) throws {
        logger.info("Deleting DNS domain: \(name)")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DNSError.invalidDomainName
        }

        let filePath = "\(Self.resolverDirectory)/\(Self.filePrefix)\(trimmed)"

        let script = """
        do shell script "rm -f \(filePath) && killall -HUP mDNSResponder" with administrator privileges
        """

        try Self.runAppleScript(script)
        logger.info("DNS domain deleted: \(name)")
    }

    // MARK: - Private

    private static func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw DNSError.scriptCreationFailed
        }
        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw DNSError.scriptExecutionFailed(message)
        }
    }

    // MARK: - Errors

    public enum DNSError: LocalizedError {
        case invalidDomainName
        case scriptCreationFailed
        case scriptExecutionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidDomainName:
                return "Domain name cannot be empty."
            case .scriptCreationFailed:
                return "Failed to create AppleScript."
            case .scriptExecutionFailed(let message):
                return message
            }
        }
    }
}
