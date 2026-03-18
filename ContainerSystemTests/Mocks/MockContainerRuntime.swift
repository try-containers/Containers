//
//  MockContainerRuntime.swift
//  ContainerSystemTests
//
//  Mock runtime for isolated testing without real container operations.
//

import Foundation
import Containerization
import ContainerizationOCI
import Logging

@testable import ContainerSystem

/// Mock runtime that provides isolated services for testing.
///
/// Creates real but lightweight service instances backed by temporary
/// directories.  All stores (ContentStore, ImageStore) are filesystem-only
/// and safe to use in a test host without special entitlements.
@MainActor
final class MockContainerRuntime: ContainerRuntime {

    init() {
        super.init(forTesting: true)
    }

    // Override start to set up isolated services in a temp directory
    override func start(appRoot: URL) async throws {
        guard !isRunning && !isStarting else {
            return
        }

        isStarting = true
        defer { isStarting = false }

        // Create directory structure
        let fm = FileManager.default
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)

        let imagesRoot = appRoot.appendingPathComponent("images")
        try fm.createDirectory(at: imagesRoot, withIntermediateDirectories: true)

        // Set appRoot so getAppRoot() works
        self.appRoot = appRoot

        // Create stores — these are filesystem-only and safe in test hosts
        let localContentStore = try LocalContentStore(
            path: imagesRoot.appendingPathComponent("content")
        )
        let imageStore = try ImageStore(path: imagesRoot, contentStore: localContentStore)
        let snapshotsPath = imagesRoot.appendingPathComponent("snapshots")

        let images = try ImagesService(
            contentStore: localContentStore,
            imageStore: imageStore,
            snapshotsPath: snapshotsPath,
            log: ContainerRuntime.logger
        )
        self.imagesService = images
        self.contentStore = localContentStore

        // ContainersService — reads existing containers from disk (empty in tests)
        self.containersService = try ContainersService(
            appRoot: appRoot,
            imagesService: images,
            log: ContainerRuntime.logger
        )

        // KernelService — just creates a directory
        self.kernelService = try KernelService(
            log: ContainerRuntime.logger,
            appRoot: appRoot
        )

        servicesInitialized = true
        isRunning = true
        startupError = nil
    }

    // Override stop to clean up
    override func stop() async throws {
        guard isRunning && !isStopping else {
            return
        }

        isStopping = true
        defer { isStopping = false }

        containersService = nil
        imagesService = nil
        kernelService = nil
        contentStore = nil
        servicesInitialized = false
        isRunning = false

        // Clean up temp directory
        if let root = appRoot {
            try? FileManager.default.removeItem(at: root)
            self.appRoot = nil
        }
    }
}


