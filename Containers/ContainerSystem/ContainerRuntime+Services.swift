//
//  ContainerRuntime+Services.swift
//  Containers
//
//  Service lifecycle management extension for ContainerRuntime.
//  Handles initialization and shutdown of container services.
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import ContainerAPIService
import ContainerPlugin
import ContainerNetworkService
import ContainerImagesService
import ContainerAPIClient
import Containerization
import ContainerizationError
import ContainerizationOCI

extension ContainerRuntime {
    
    // MARK: - Service Lifecycle
    
    /// Initialize all services for sandboxed mode
    internal func initializeServices(appRoot: URL) async throws {
        guard !servicesInitialized else {
            Self.logger.info("Services already initialized")
            return
        }
        
        Self.logger.info("Initializing services (sandboxed mode)...")
        Self.logger.info("App root: \(appRoot.path)")
        
        // Initialize images service (must come before containers service)
        Self.logger.info("Initializing images service...")
        let imagesRoot = appRoot.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesRoot, withIntermediateDirectories: true)

        let imageStore = try ImageStore(path: imagesRoot)
        let snapshotStore = try SnapshotStore(path: imagesRoot, unpackStrategy: SnapshotStore.defaultUnpackStrategy, log: Self.logger)
        let contentStore = try LocalContentStore(path: imagesRoot.appendingPathComponent("content"))
        
        let images = try ImagesService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotStore: snapshotStore,
            log: Self.logger
        )
        self.imagesService = images
        self.contentStore = contentStore
        Self.logger.info("Images service initialized")

        // Initialize sandboxed containers service
        Self.logger.info("Initializing sandboxed containers service...")
        let sandboxedContainers = try SandboxedContainersService(appRoot: appRoot, imagesService: images, log: Self.logger)
        self.sandboxedContainersService = sandboxedContainers
        Self.logger.info("Sandboxed containers service initialized")
        
        // Initialize kernel service
        Self.logger.info("Initializing kernel service...")
        let kernel = try KernelService(log: Self.logger, appRoot: appRoot)
        self.kernelService = kernel
        Self.logger.info("Kernel service initialized")
        
        Self.logger.info("Built-in NAT networking (sandboxed mode)")
        
        servicesInitialized = true
        Self.logger.info("Services initialized successfully")
    }
    
    /// Shutdown all services
    internal func shutdownServices() async {
        Self.logger.info("Shutting down services...")
        
        // Stop all running containers
        if let sandboxedContainers = sandboxedContainersService {
            let list = await sandboxedContainers.list()
            for container in list where container.status == .running {
                Self.logger.info("Stopping container: \(container.configuration.id)")
                do {
                    try await sandboxedContainers.stop(id: container.configuration.id, options: .default)
                } catch {
                    Self.logger.error("Error stopping container \(container.configuration.id): \(error)")
                }
            }
        }
        
        containersService = nil
        sandboxedContainersService = nil
        imagesService = nil
        kernelService = nil
        contentStore = nil
        pluginLoader = nil
        servicesInitialized = false
        
        Self.logger.info("Services shut down")
    }
    
}
