//
//  ContainerRuntime.swift
//  Containers
//
//  Manages the container system lifecycle and services
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import ContainerImagesService
import ContainerAPIService
import ContainerPlugin
import ContainerPersistence
import ContainerizationError
import ContainerizationOCI
import Logging

/// Manages the container runtime lifecycle and services.
/// Owns all services and provides factory methods for creating managers.
/// Similar to Apple's API Server but running in-process.

@Observable
@MainActor
internal class ContainerRuntime {
    
    // MARK: - Singleton
    
    /// Shared runtime instance - internal to ContainerSystem module
    internal static let shared = ContainerRuntime()
    
    /// Private initializer - forces use of singleton in production
    private init() {}
    
    #if DEBUG
    /// Internal initializer for testing - allows subclassing
    internal init(forTesting: Bool) {
        // Empty initializer for test subclasses
    }
    #endif
    
    // MARK: - Nested Types
    
    internal struct PluginProcessInfo {
        let process: Foundation.Process
        let plugin: ContainerPlugin.Plugin
        let instanceId: String
        let standardOutput: Pipe?
        let standardError: Pipe?
    }
    
    // MARK: - Observable State
    
    internal var isRunning: Bool = false
    internal var isStarting: Bool = false
    internal var isStopping: Bool = false
    internal var startupError: Error?
    
    // Plugin processes storage (used by ContainerRuntime+Plugins extension)
    internal var pluginProcesses: [String: PluginProcessInfo] = [:]
    
    // Service storage (used by ContainerRuntime+Services extension)
    internal var servicesInitialized = false
    internal var pluginLoader: ContainerPlugin.PluginLoader?
    internal var containersService: ContainerAPIService.ContainersService?
    internal var sandboxedContainersService: SandboxedContainersService?
    internal var imagesService: ContainerImagesService.ImagesService?
    internal var kernelService: ContainerAPIService.KernelService?
    internal var contentStore: ContentStore?

    // System status for UI
    internal enum SystemStatus: Equatable {
        case notStarted
        case starting
        case running
        case stopping
        case failed
    }
    
    internal var systemStatus: SystemStatus {
        if isStopping {
            return .stopping
        } else if isStarting {
            return .starting
        } else if isRunning {
            return .running
        } else if startupError != nil {
            return .failed
        } else {
            return .notStarted
        }
    }
    
    // MARK: - Service Manager
    
    // ServiceManager is a @MainActor singleton that manages services
    
    // Current configuration
    private var appRoot: URL?
    
    internal static let logger: Logger = {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        var logger = Logger(label: "app.containers.system")
#if DEBUG
        logger.logLevel = .info
#else
        logger.logLevel = .error
#endif
        return logger
    }()
    
    // MARK: - Service Accessors
    
    /// Get containers service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    internal func getContainersService() async throws -> SandboxedContainersService {
        guard let service = sandboxedContainersService else {
            throw ContainerizationError(.internalError, message: "Containers service not initialized")
        }
        return service
    }
    
    /// Get images service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    internal func getImagesService() async throws -> ImagesService {
        guard let service = imagesService else {
            throw ContainerizationError(.internalError, message: "Images service not initialized")
        }
        return service
    }
    
    /// Get kernel service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    internal func getKernelService() async throws -> KernelService {
        guard let service = kernelService else {
            throw ContainerizationError(.internalError, message: "Kernel service not initialized")
        }
        return service
    }
    
    /// Get app root directory. Only accessible to managers in ContainerSystem module.
    internal func getAppRoot() throws -> URL {
        guard let appRoot = appRoot else {
            throw ContainerizationError(.internalError, message: "App root not initialized")
        }
        return appRoot
    }
    
    /// Get content store. Only accessible to managers in ContainerSystem module.
    internal func getContentStore() throws -> ContentStore {
        guard let contentStore = contentStore else {
            throw ContainerizationError(.internalError, message: "Content store not initialized")
        }
        return contentStore
    }
    
    // MARK: - Internal API
    
    /// Start the container system and initialize all managers
    internal func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            Self.logger.info("System already running or starting")
            return
        }
        
        Self.logger.info("Starting container system...")
        
        self.isStarting = true
        self.startupError = nil
        self.appRoot = appRoot
        
        defer {
            isStarting = false
        }
        
        do {
            // Create necessary directories
            Self.logger.info("Creating data directories...")
            try createDataDirectories(appRoot: appRoot)
            
            // Initialize services
            Self.logger.info("Initializing services...")
            try await initializeServices(appRoot: appRoot)
            Self.logger.info("Services initialized")
            
            // Install prerequisites (init image and kernel)
            try await installPrerequisites()
            
            isRunning = true
            startupError = nil
            Self.logger.info("Container system started successfully")
            
        } catch {
            isRunning = false
            startupError = error
            self.appRoot = nil
            
            // Cleanup on failure
            stopAllPlugins()
            
            Self.logger.error("Failed to start system: \(error)")
            throw error
        }
    }
    
    /// Stop the container system and all managers
    internal func stop() async throws {
        guard isRunning && !isStopping else {
            Self.logger.info("System not running or already stopping")
            return
        }
        
        isStopping = true
        defer { isStopping = false }
        
        Self.logger.info("Stopping container system...")
        
        // Stop all plugins
        stopAllPlugins()
        
        // Shutdown services
        await shutdownServices()
        
        isRunning = false
        appRoot = nil
        
        Self.logger.info("Container system stopped")
    }
    
    // MARK: - Private Helpers
    
    private func createDataDirectories(appRoot: URL) throws {
        // Create app data directory with subdirectories
        try FileManager.default.createDirectory(
            at: appRoot,
            withIntermediateDirectories: true
        )
        
        // Create content directory (for image storage)
        try FileManager.default.createDirectory(
            at: appRoot.appendingPathComponent("content"),
            withIntermediateDirectories: true
        )
    }
}
