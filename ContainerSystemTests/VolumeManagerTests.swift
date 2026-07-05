//
//  VolumeManagerTests.swift
//  ContainerSystemTests
//
//  Created by Axel Martinez on 2026/02/08.
//

import ContainerizationError
import Foundation
import Testing

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

    @Test("List volumes returns empty array initially")
    @MainActor
    func testListVolumes() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)
        let volumes = try await manager.list()

        #expect(volumes.isEmpty)
    }

    // MARK: - Create Volume Tests

    @Test("Create volume succeeds and is listed")
    @MainActor
    func testCreateVolume() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024  // 1 MB
        )

        #expect(volume.name == volumeName)
        #expect(volume.driver == "local")
        #expect(volume.format == "ext4")
        #expect(volume.source.hasSuffix("volume.ext4"))
        #expect(volume.sizeInBytes == 1024 * 1024)

        let volumes = try await manager.list()
        #expect(volumes.contains(where: { $0.name == volumeName }))
    }

    @Test("Create volume without size uses default size")
    @MainActor
    func testCreateVolumeWithoutSize() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: nil
        )

        #expect(volume.source.hasSuffix("volume.ext4"))
        #expect(volume.sizeInBytes == VolumeStorage.defaultVolumeSizeBytes)

        let volumes = try await manager.list()
        #expect(
            volumes.first(where: { $0.name == volumeName })?.sizeInBytes
                == VolumeStorage.defaultVolumeSizeBytes
        )
    }

    @Test("Create volume with invalid name throws error")
    @MainActor
    func testCreateVolumeInvalidName() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)

        await #expect(throws: VolumeError.self) {
            _ = try await manager.create(
                name: "invalid name!",
                labels: [],
                options: [],
                sizeInBytes: nil
            )
        }
    }

    @Test("Create duplicate volume throws error")
    @MainActor
    func testCreateDuplicateVolume() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        _ = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        await #expect(throws: VolumeError.self) {
            _ = try await manager.create(
                name: volumeName,
                labels: [],
                options: [],
                sizeInBytes: 1024 * 1024
            )
        }
    }

    // MARK: - Delete Volume Tests

    @Test("Delete empty volume list succeeds")
    @MainActor
    func testDeleteEmptyVolumeList() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let manager = VolumeManager(testRuntime: testRuntime)

        try await manager.delete(volumes: [])
    }

    @Test("Delete volume removes it from list")
    @MainActor
    func testDeleteVolume() async throws {
        let (_, testRuntime) = try await setupTestSystem()

        let volumeName = "test-volume-\(UUID().uuidString)"
        let manager = VolumeManager(testRuntime: testRuntime)

        let volume = try await manager.create(
            name: volumeName,
            labels: [],
            options: [],
            sizeInBytes: 1024 * 1024
        )

        try await manager.delete(volumes: [volume])

        let volumes = try await manager.list()
        #expect(!volumes.contains(where: { $0.name == volumeName }))
    }
}
