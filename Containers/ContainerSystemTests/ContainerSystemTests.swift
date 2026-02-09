//
//  ContainerSystemTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Testing
import Foundation

@testable import ContainerSystem

@Suite(.serialized)
struct ContainerSystemTests {
    
    @Test("System starts successfully")
    @MainActor
    func testSystemStart() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        try await system.start(appRoot: appRoot)
        
        #expect(system.isRunning == true)
        #expect(system.systemStatus == .running)
        
        try await system.stop()
    }
    
    @Test("System can be started multiple times")
    @MainActor
    func testSystemMultipleStarts() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        try await system.start(appRoot: appRoot)
        #expect(system.isRunning == true)
        
        // Starting again should not cause error
        try await system.start(appRoot: appRoot)
        #expect(system.isRunning == true)
        
        try await system.stop()
    }
    
    @Test("System stops successfully")
    @MainActor
    func testSystemStop() async throws {
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        
        // Ensure system is started
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        try await system.start(appRoot: appRoot)
        #expect(system.isRunning == true)
        
        // Stop the system
        try await system.stop()
        
        #expect(system.isRunning == false)
        #expect(system.systemStatus == .notStarted)
    }
}
