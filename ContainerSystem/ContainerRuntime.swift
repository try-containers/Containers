//
//  ContainerRuntime.swift
//  Containers
//
//  Manages the container system lifecycle and services
//
//  Created by Axel Martinez on 2026/02/04.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging

/// Manages the container runtime lifecycle and services.
/// Owns all services and provides factory methods for creating managers.
@Observable
@MainActor
class ContainerRuntime {
    /// Shared runtime instance - internal to ContainerSystem module
    static let shared = ContainerRuntime()

    /// Private initializer - forces use of singleton in production
    private init() {
        _ = Self._bootstrapLogging
        var l = Logger(label: "app.containers.system")
        #if DEBUG
        l.logLevel = .debug
        #else
        l.logLevel = .info
        #endif
        self.logger = l
    }

    #if DEBUG
    /// Internal initializer for testing - allows subclassing
    init(forTesting: Bool) {
        _ = Self._bootstrapLogging
        var l = Logger(label: "app.containers.system.test")
        l.logLevel = .debug
        self.logger = l
    }
    #endif

    // MARK: - Nested Types

    struct PluginProcessInfo {
        let process: Foundation.Process
        let plugin: Plugin
        let instanceId: String
        let standardOutput: Pipe?
        let standardError: Pipe?
    }

    // MARK: - Observable State

    var isRunning: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var startupError: Error?

    /// Timestamp of last container state change
    /// All ContainerManager instances observe this property
    var lastContainerStateChange: Date = Date()

    /// What a long-running operation (pull, build, unpack) is doing, which
    /// every manager reports into and every sheet reads from.
    let progress = ProgressReporter()

    // Plugin processes storage (used by ContainerRuntime+Plugins extension)
    var pluginProcesses: [String: PluginProcessInfo] = [:]

    // Current configuration
    var appRoot: URL?
    var isAccessingAppRootSecurityScope = false

    // MARK: - Private State

    // Service storage (used by ContainerRuntime+Services extension)
    private var servicesInitialized = false
    private var pluginLoader: PluginLoader?
    private var containersService: ContainersService?
    private var imagesService: ImagesService?
    private var kernelService: KernelService?
    private var contentStore: ContentStore?

    let logger: Logger

    private static let _bootstrapLogging: Void = LoggingSystem.bootstrap { label in
        let category = label.split(separator: ".").last.map(String.init) ?? label
        return OSLogHandler(subsystem: "app.containers", category: category)
    }

    // MARK: - Service Accessors
    /// Get containers service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    func getContainersService() async throws -> ContainersService {
        guard let service = containersService else {
            throw ContainerizationError(
                .internalError,
                message: "Containers service not initialized"
            )
        }
        return service
    }

    /// Get images service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    func getImagesService() async throws -> ImagesService {
        guard let service = imagesService else {
            throw ContainerizationError(
                .internalError,
                message: "Images service not initialized"
            )
        }

        return service
    }

    /// Get kernel service. Only accessible to managers in ContainerSystem module.
    /// Can be overridden in tests to provide mock services.
    func getKernelService() async throws -> KernelService {
        guard let service = kernelService else {
            throw ContainerizationError(
                .internalError,
                message: "Kernel service not initialized"
            )
        }

        return service
    }

    /// Get app root directory. Only accessible to managers in ContainerSystem module.
    func getAppRoot() throws -> URL {
        guard let appRoot = appRoot else {
            throw ContainerizationError(
                .internalError,
                message: "App root not initialized"
            )
        }

        return appRoot
    }

    /// Get content store. Only accessible to managers in ContainerSystem module.
    func getContentStore() throws -> ContentStore {
        guard let contentStore = contentStore else {
            throw ContainerizationError(
                .internalError,
                message: "Content store not initialized"
            )
        }

        return contentStore
    }

    // MARK: - Internal API

    /// Start the container system and initialize all managers
    func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            logger.info("System already running or starting")
            return
        }

        logger.info("Starting container system...")

        self.isStarting = true
        self.startupError = nil
        self.appRoot = appRoot
        self.isAccessingAppRootSecurityScope =
            appRoot.startAccessingSecurityScopedResource()

        defer {
            isStarting = false
        }

        do {
            // Create necessary directories
            try createDataDirectories(appRoot: appRoot)

            // Initialize services
            try await initializeServices(appRoot: appRoot)

            // Install prerequisites (init image and kernel)
            try await installPrerequisites()

            isRunning = true
            startupError = nil

            logger.info("Container system started successfully")

        } catch {
            self.isRunning = false
            self.startupError = error
            if isAccessingAppRootSecurityScope {
                appRoot.stopAccessingSecurityScopedResource()
                isAccessingAppRootSecurityScope = false
            }
            self.appRoot = nil

            // Cleanup on failure
            stopAllPlugins()

            logger.error("Failed to start system: \(error)")

            throw error
        }
    }

    /// Stop the container system and all managers
    func stop() async throws {
        guard isRunning && !isStopping else {
            logger.info("System not running or already stopping")
            return
        }

        isStopping = true

        defer { isStopping = false }

        logger.info("Stopping container system...")

        // Stop all plugins
        stopAllPlugins()

        // Shutdown services
        await shutdownServices()

        isRunning = false
        if isAccessingAppRootSecurityScope {
            appRoot?.stopAccessingSecurityScopedResource()
            isAccessingAppRootSecurityScope = false
        }
        appRoot = nil

        logger.info("Container system stopped")
    }

    // MARK: - Private Helpers

    /// Initialize all services for sandboxed mode
    private func initializeServices(appRoot: URL) async throws {
        guard !servicesInitialized else {
            logger.info("Services already initialized")
            return
        }

        logger.info("Initializing services...")

        // Initialize images service (must come before containers service)
        let imagesRoot = appRoot.appendingPathComponent("images")

        try FileManager.default.createDirectory(
            at: imagesRoot,
            withIntermediateDirectories: true
        )

        let contentStore = try LocalContentStore(
            path: imagesRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(
            path: imagesRoot,
            contentStore: contentStore
        )
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")
        let imagesService = try ImagesService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: logger
        )

        self.imagesService = imagesService
        self.contentStore = contentStore

        // Initialize sandboxed containers service
        let service = try ContainersService(
            appRoot: appRoot,
            imagesService: imagesService,
            log: logger
        )

        self.containersService = service

        // Initialize kernel service
        let kernel = try KernelService(log: logger, appRoot: appRoot)

        self.kernelService = kernel

        servicesInitialized = true

        logger.info("Services initialized successfully")

        // Register callback to update runtime state when containers change
        await service.addStateChangeCallback { @MainActor [weak self] in
            guard let self = self else { return }

            self.lastContainerStateChange = Date()
        }
    }

    /// Shutdown all services
    private func shutdownServices() async {
        // Stop all running containers
        if let service = containersService {
            let list = await service.list()
            for container in list where container.status == .running {
                do {
                    try await service.stop(
                        id: container.configuration.id,
                        options: .default
                    )
                } catch {
                    logger.error(
                        "Error stopping container \(container.configuration.id): \(error)"
                    )
                }
            }
        }

        containersService = nil
        imagesService = nil
        kernelService = nil
        contentStore = nil
        pluginLoader = nil
        servicesInitialized = false
    }

    private func createDataDirectories(appRoot: URL) throws {
        logger.info("Creating data directories...")

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
