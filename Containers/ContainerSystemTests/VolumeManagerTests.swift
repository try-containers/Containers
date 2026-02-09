//
//  VolumeManagerTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Testing
import Foundation
import ContainerResource
import ContainerizationError

@testable import ContainerSystem

@Suite(.serialized)
struct VolumeManagerTests {
    
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
    
    // MARK: - List Volumes Tests
    
    @Test("List volumes returns array")
    @MainActor
    func testListVolumes() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let manager = VolumeManager(testRuntime: testRuntime)
        let volumes = try await manager.list()
        
        #expect(type(of: volumes) == [Volume].self)
    }
    
    // MARK: - Create Volume Tests
    
    @Test("Create volume throws unsupported error in sandboxed mode")
    @MainActor
    func testCreateVolume() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)
        
        do {
            _ = try await manager.create(
                name: volumeName,
                labels: [],
                options: [],
                sizeInBytes: nil
            )
            
            Issue.record("Expected ContainerizationError for unsupported operation")
        } catch let error as ContainerizationError {
            #expect(error.code == .internalError)
            #expect(error.message.contains("not yet supported"))
        }
    }
    
    // MARK: - Delete Volume Tests
    
    @Test("Delete volumes throws unsupported error in sandboxed mode")
    @MainActor
    func testDeleteEmptyVolumeList() async throws {
        let (_, testRuntime) = try await setupTestSystem()
        
        let manager = VolumeManager(testRuntime: testRuntime)
        
        do {
            try await manager.delete(volumes: [])
            
            Issue.record("Expected ContainerizationError for unsupported operation")
        } catch let error as ContainerizationError {
            #expect(error.code == .internalError)
            #expect(error.message.contains("not yet supported"))
        }
    }
}
