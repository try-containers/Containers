//
//  ContainersServiceTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Testing
import Foundation
@testable import ContainerSystem

@Suite(.serialized)
struct ContainersServiceTests {
    
    @Test("Service initializes successfully")
    @MainActor
    func testServiceInitialization() async throws {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        
        try await system.start(appRoot: appRoot)
        
        #expect(system.isRunning == true)
        
        try await system.stop()
    }
    
    @Test("Service can be stopped")
    @MainActor
    func testServiceStop() async throws {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")
        
        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        try await system.start(appRoot: appRoot)
        
        #expect(system.isRunning == true)
        
        try await system.stop()
        
        #expect(system.isRunning == false)
    }
}
