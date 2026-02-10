//
//  MockContainerRuntime.swift
//  ContainerSystemTests
//
//  Mock runtime for isolated testing without real container operations
//

import Foundation
import ContainerAPIService
import ContainerImagesService
import ContainerResource
import ContainerizationOCI
import ContainerizationOS
import Containerization

@testable import ContainerSystem

/// Mock runtime that provides stub services for testing
@MainActor
final class MockContainerRuntime: ContainerRuntime {
    
    // Mock service instances - we'll create these with proper initializers
    private var mockContainersService: SandboxedContainersService?
    private var mockImagesService: ImagesService?
    private var mockKernelService: KernelService?
    private let tempAppRoot: URL
    
    init() {
        // Create a unique temp directory for this mock runtime
        self.tempAppRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-runtime-\(UUID().uuidString)")
        super.init(forTesting: true)
    }
    
    // Override start to set up minimal real services that won't do actual work
    override func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            return
        }
        
        isStarting = true
        defer { isStarting = false }
        
        // Create minimal directory structure
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appRoot.appendingPathComponent("images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appRoot.appendingPathComponent("images/content"), withIntermediateDirectories: true)
        
        // Initialize real but isolated services
        let imagesRoot = appRoot.appendingPathComponent("images")
        let imageStore = try ImageStore(path: imagesRoot)
        let snapshotStore = try SnapshotStore(path: imagesRoot, unpackStrategy: SnapshotStore.defaultUnpackStrategy, log: ContainerRuntime.logger)
        let contentStore = try LocalContentStore(path: imagesRoot.appendingPathComponent("content"))
        
        mockImagesService = try ImagesService(
            contentStore: contentStore,
            imageStore: imageStore,
            snapshotStore: snapshotStore,
            log: ContainerRuntime.logger
        )
        
        mockContainersService = try SandboxedContainersService(
            appRoot: appRoot,
            imagesService: mockImagesService!,
            log: ContainerRuntime.logger
        )
        
        mockKernelService = try KernelService(log: ContainerRuntime.logger, appRoot: appRoot)
        
        servicesInitialized = true
        isRunning = true
        startupError = nil
    }
    
    // Override stop to clean up mock services
    override func stop() async throws {
        guard isRunning && !isStopping else {
            return
        }
        
        isStopping = true
        defer { isStopping = false }
        
        mockContainersService = nil
        mockImagesService = nil
        mockKernelService = nil
        servicesInitialized = false
        isRunning = false
        
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempAppRoot)
    }
    
    // Override service getters to return our isolated mock services
    override func getContainersService() async throws -> SandboxedContainersService {
        guard let service = mockContainersService else {
            throw NSError(domain: "MockRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock service not initialized"])
        }
        return service
    }
    
    override func getImagesService() async throws -> ImagesService {
        guard let service = mockImagesService else {
            throw NSError(domain: "MockRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock service not initialized"])
        }
        return service
    }
    
    override func getKernelService() async throws -> KernelService {
        guard let service = mockKernelService else {
            throw NSError(domain: "MockRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock service not initialized"])
        }
        return service
    }
}



