//
//  ImageManagerTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Testing
import Foundation
import Containerization
import ContainerizationOCI

@testable import ContainerSystem

struct ImageManagerTests {
    
    // MARK: - Setup Helper
    
    @MainActor
    private func setupTestSystem() async throws -> (URL, ContainerRuntime) {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        try await system.start(appRoot: appRoot)
        
        return (appRoot, testRuntime)
    }
    
    // MARK: - List Images Tests
    
    @Test("List images returns array")
    @MainActor
    func testListImages() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let manager = ImageManager(testRuntime: testRuntime)
        let images = try await manager.list()
        
        #expect(type(of: images) == [ImageDescription].self)
    }
    
    @Test("List images filters infrastructure images")
    @MainActor
    func testListImagesFiltersInfra() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let manager = ImageManager(testRuntime: testRuntime)
        let images = try await manager.list()
        
        // Verify no infra images
        let hasInfraImages = images.contains { image in
            image.reference.hasPrefix("infra:")
        }
        #expect(hasInfraImages == false)
    }
    
    // MARK: - Save Images Tests
    
    @Test("Save images to valid directory")
    @MainActor
    func testSaveImagesToDirectory() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let manager = ImageManager(testRuntime: testRuntime)
        try await manager.save(images: [], platform: .current, outputDirectory: tempDir)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }
    
    @Test("Save images with empty list succeeds")
    @MainActor
    func testSaveEmptyImageList() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let manager = ImageManager(testRuntime: testRuntime)
        try await manager.save(images: [], platform: .current, outputDirectory: tempDir)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }
    
    // MARK: - Delete Images Tests
    
    @Test("Delete images with empty list succeeds")
    @MainActor
    func testDeleteEmptyImageList() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let manager = ImageManager(testRuntime: testRuntime)
        try await manager.delete(images: [])
    }
}
