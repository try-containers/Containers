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
        
        Self.logger.info("Initializing services...")
        
        // Initialize images service (must come before containers service)
        let imagesRoot = appRoot.appendingPathComponent("images")
        
        try FileManager.default.createDirectory(at: imagesRoot, withIntermediateDirectories: true)

        let contentStore = try LocalContentStore(path: imagesRoot.appendingPathComponent("content"))
        let imageStore = try ImageStore(path: imagesRoot, contentStore: contentStore)
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")
        let imagesService = try ImagesService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: Self.logger
        )
        
        self.imagesService = imagesService
        self.contentStore = contentStore

        // Initialize sandboxed containers service
        let service = try ContainersService(appRoot: appRoot, imagesService: imagesService, log: Self.logger)
        
        self.containersService = service
        
        // Initialize kernel service
        let kernel = try KernelService(log: Self.logger, appRoot: appRoot)
        
        self.kernelService = kernel
        
        servicesInitialized = true
        
        Self.logger.info("Services initialized successfully")
        
        // Register callback to update runtime state when containers change
        await service.addStateChangeCallback { @MainActor [weak self] in
            guard let self = self else { return }
            
            self.lastContainerStateChange = Date()
        }
    }
    
    /// Shutdown all services
    internal func shutdownServices() async {
        // Stop all running containers
        if let service = containersService {
            let list = await service.list()
            for container in list where container.status == .running {
                do {
                    try await service.stop(id: container.configuration.id, options: .default)
                } catch {
                    Self.logger.error("Error stopping container \(container.configuration.id): \(error)")
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
    
}
