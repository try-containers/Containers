//
//  VolumeManager.swift
//  Containers
//
//  Manager for volume operations
//  Architecture: Actor singleton (volumes not yet implemented in sandboxed mode)
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import Observation
import ContainerAPIService
import ContainerBuild
import ContainerNetworkService
import ContainerPersistence
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import ContainerizationOS
import ContainerResource
import Logging

/// Manages volume operations.
/// Create instances via public init() - automatically references shared runtime.
/// Note: Volume management not yet implemented in sandboxed mode.
@Observable
@MainActor
public final class VolumeManager {
    
    /// Internal runtime reference (hidden from UI)
    internal let runtime: ContainerRuntime
    private let logger: Logger
    
    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        var logger = Logger(label: "app.containers.manager.volumes")
        logger.logLevel = .info
        self.logger = logger
    }
    
    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    internal init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        var logger = Logger(label: "app.containers.manager.volumes.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif
    
    // MARK: - Public API
    
    @discardableResult
    public func create(
        name: String,
        labels: [KeyValue],
        options: [KeyValue],
        sizeInBytes: UInt64?
    ) async throws -> Volume {
        throw ContainerizationError(.internalError, message: "Volume management not yet supported in sandboxed mode")
    }
    
    public func list() async throws -> [Volume] {
        // For now, return empty list
        return []
    }
    
    public func delete(volumes: [Volume]) async throws {
        throw ContainerizationError(.internalError, message: "Volume management not yet supported in sandboxed mode")
    }
}
