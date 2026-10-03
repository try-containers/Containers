//
//  ContainersServiceTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Testing

@testable import ContainerSystem

@Suite("Containers service", .serialized)
struct ContainersServiceTests {

    @Test("Initialize service")
    @MainActor
    func initializeService() async throws {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)

        try await system.start(appRoot: appRoot)

        #expect(system.status == .running)

        try await system.stop()
    }

    @Test("Stop service")
    @MainActor
    func stopService() async throws {
        let appRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-containers-\(UUID().uuidString)")

        let testRuntime = MockContainerRuntime()
        let system = SystemManager(testRuntime: testRuntime)
        try await system.start(appRoot: appRoot)

        #expect(system.status == .running)

        try await system.stop()

        #expect(system.status == .notStarted)
    }
}
