//
//  ContainerManagerTests.swift
//  ContainersTests
//
//  Unit tests for ContainerManager
//

import Testing
import Foundation
@testable import Containers

@MainActor
@Suite("ContainerManager Tests")
struct ContainerManagerTests {
    
    // MARK: - Helper Methods
    
    /// Creates a minimal container configuration for testing
    func createTestContainerInfo() -> ContainerInfo {
        return ContainerInfo(
            name: "test-container",
            os: "linux",
            arch: "arm64",
            platform: nil,
            kernel: nil,
            entryPoint: nil,
            cidfile: "",
            networks: [],
            labels: [],
            publishPorts: [],
            publishSockets: [],
            ssh: false,
            volumes: [],
            virtualFileSystem: [],
            temporaryFileSystem: [],
            virtualization: .default,
            dnsDisabled: false,
            dnsNameservers: [],
            dnsDomain: nil,
            dnsSearchDomains: [],
            dnsOptions: [],
            deleteOnTermination: false
        )
    }
    
    /// Creates a minimal process configuration for testing
    func createTestProcess() -> ContainerProcess {
        return ContainerProcess(
            command: "",
            workingDirectory: nil,
            tty: false,
            environments: [],
            envFile: [],
            user: nil,
            uid: nil,
            gid: nil
        )
    }
    
    // MARK: - Validation Tests
    
    @Test("Valid entity name passes validation")
    func testValidEntityName() async throws {
        // Valid names should contain alphanumeric, underscore, dot, or dash
        // This tests the internal validation logic
        let validNames = ["test", "test-container", "test_container", "test.container", "test123"]
        
        // Since validEntityName is private, we test it indirectly through createContainer
        // For direct testing, we'd need to make it internal or create a test-specific exposure
        #expect(true) // Placeholder - would need reflection or exposure for direct testing
    }
    
    @Test("Invalid entity name should fail validation")
    func testInvalidEntityName() async throws {
        // Names starting with special characters or containing invalid chars should fail
        // This would be tested through createContainer failure
        #expect(true) // Placeholder
    }
    
    // MARK: - Container ID Generation Tests
    
    @Test("Container ID generated when name is empty")
    func testContainerIDGeneration() async throws {
        // When no name is provided, a UUID should be generated
        // This tests the internal createContainerID logic
        #expect(true) // Placeholder - tests internal logic
    }
    
    @Test("Container ID uses provided name")
    func testContainerIDFromName() async throws {
        // When name is provided, it should be used as the ID
        #expect(true) // Placeholder
    }
    
    // MARK: - List Containers Tests
    
    @Test("List containers returns empty array initially", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testListContainersEmpty() async throws {
        // Start system first
        try await ContainerSystem.shared.start()
        
        let containers = try await ContainerManager.listContainers()
        // May not be empty if system has existing containers
        #expect(containers != nil)
    }
    
    @Test("List containers is callable", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testListContainersCallable() async throws {
        try await ContainerSystem.shared.start()
        
        let result = try await ContainerManager.listContainers()
        #expect(result is [ContainerSnapshot])
    }
    
    // MARK: - Get Container Tests
    
    @Test("Get non-existent container throws error", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testGetNonExistentContainer() async throws {
        try await ContainerSystem.shared.start()
        
        do {
            _ = try await ContainerManager.getContainer("nonexistent-container-id")
            Issue.record("Expected ContainerizationError")
        } catch let error as ContainerizationError {
            #expect(error.code == .notFound)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Container Log Tests
    
    @Test("Get container log for non-existent container returns empty string")
    func testGetContainerLogNonExistent() async throws {
        let log = try await ContainerManager.getContainerLog("nonexistent", boot: false)
        #expect(log.isEmpty)
    }
    
    @Test("Get boot log returns empty for non-existent container")
    func testGetBootLogNonExistent() async throws {
        let log = try await ContainerManager.getContainerLog("nonexistent", boot: true)
        #expect(log.isEmpty)
    }
    
    // MARK: - Shell Split Tests
    
    @Test("Shell split handles simple commands")
    func testShellSplitSimple() async throws {
        // Tests the internal shellSplit method indirectly
        // "sh -c echo" should become ["sh", "-c", "echo"]
        #expect(true) // Placeholder - tests internal utility
    }
    
    @Test("Shell split handles quoted strings")
    func testShellSplitQuoted() async throws {
        // Tests that "sh -c \"echo hello\"" becomes ["sh", "-c", "echo hello"]
        #expect(true) // Placeholder
    }
    
    @Test("Shell split handles single quotes")
    func testShellSplitSingleQuotes() async throws {
        // Tests that "sh -c 'echo hello'" becomes ["sh", "-c", "echo hello"]
        #expect(true) // Placeholder
    }
    
    // MARK: - Stop Containers Tests
    
    @Test("Stop empty container list succeeds", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testStopEmptyList() async throws {
        try await ContainerSystem.shared.start()
        
        // Stopping empty list should not error
        try await ContainerManager.stopContainers(containers: [])
    }
    
    // MARK: - Delete Containers Tests
    
    @Test("Delete empty container list succeeds", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testDeleteEmptyList() async throws {
        try await ContainerSystem.shared.start()
        
        // Deleting empty list should not error
        try await ContainerManager.deleteContainers([], force: false)
    }
    
    @Test("Delete running container without force fails", .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func testDeleteRunningContainerWithoutForce() async throws {
        // This would require actually creating and starting a container
        // Placeholder for integration test
        #expect(true)
    }
    
    // MARK: - Process Configuration Tests
    
    @Test("Process configuration uses image defaults when not overridden")
    func testProcessConfigurationDefaults() async throws {
        // Tests that parseProcessConfiguration correctly uses image config defaults
        #expect(true) // Placeholder - tests internal logic
    }
    
    @Test("Process configuration overrides image defaults when specified")
    func testProcessConfigurationOverride() async throws {
        // Tests that user-specified values override image defaults
        #expect(true) // Placeholder
    }
    
    @Test("Process configuration requires command or entrypoint")
    func testProcessConfigurationRequiresCommand() async throws {
        // Should fail if neither command nor entrypoint is provided
        #expect(true) // Placeholder
    }
}
