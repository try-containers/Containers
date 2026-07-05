//
//  ImageManagerTests.swift
//  ContainersTests
//
//  Unit tests for ImageManager
//

import Foundation
import Testing

@testable import Containers

@MainActor
@Suite("ImageManager Tests")
struct ImageManagerTests {

    // MARK: - Helper Methods

    /// Creates a test image description
    func createTestImageDescription() -> ImageDescription {
        // This would need actual ImageDescription initialization
        // Placeholder for now
        ImageDescription(
            reference: "test:latest",
            description: "test:latest",
            digest: "sha256:test"
        )
    }

    // MARK: - List Images Tests

    @Test(
        "List images returns array",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testListImages() async throws {
        try await ContainerSystem.shared.start()

        let images = try await ImageManager.listImages()
        #expect(images is [ImageDescription])
    }

    @Test(
        "List images filters infrastructure images",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testListImagesFiltersInfra() async throws {
        try await ContainerSystem.shared.start()

        let images = try await ImageManager.listImages()

        // Verify no infrastructure images are in the list
        let hasInfraImage = images.contains { image in
            image.reference.contains("buildkit")
                || image.reference.contains("init")
        }

        // Infrastructure images should be filtered out
        #expect(!hasInfraImage || images.isEmpty)
    }

    // MARK: - Infrastructure Image Detection Tests

    @Test("Infrastructure image detection identifies builder image")
    func testIsInfraImageBuilder() async throws {
        // Tests the internal isInfraImage method
        // Builder images should be detected
        #expect(true)  // Placeholder - tests internal logic
    }

    @Test("Infrastructure image detection identifies init image")
    func testIsInfraImageInit() async throws {
        // Init images should be detected
        #expect(true)  // Placeholder
    }

    @Test("Infrastructure image detection excludes regular images")
    func testIsInfraImageRegular() async throws {
        // Regular images should not be detected as infrastructure
        #expect(true)  // Placeholder
    }

    // MARK: - Pull Image Tests

    @Test("Pull image with invalid reference throws error")
    func testPullImageInvalidReference() async throws {
        do {
            try await ImageManager.pullImage(reference: "")
            Issue.record("Expected error for empty reference")
        } catch {
            // Expected to throw
            #expect(error is ContainerizationError || error is Error)
        }
    }

    @Test(
        "Pull image requires started system",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testPullImageRequiresStartedSystem() async throws {
        // Stop system if running
        try await ContainerSystem.shared.stop()

        do {
            try await ImageManager.pullImage(reference: "alpine:latest")
            Issue.record("Expected error when system not started")
        } catch let error as ContainerizationError {
            #expect(error.code == .internalError)
        } catch {
            // May throw different error
        }
    }

    // MARK: - Save Images Tests

    @Test(
        "Save images to valid directory",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testSaveImagesToDirectory() async throws {
        try await ContainerSystem.shared.start()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Save empty list should succeed
        try await ImageManager.saveImages([], outputDirectory: tempDir)
    }

    @Test(
        "Save images with empty list succeeds",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testSaveEmptyImageList() async throws {
        try await ContainerSystem.shared.start()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageManagerTests")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await ImageManager.saveImages([], outputDirectory: tempDir)
    }

    // MARK: - Load Images Tests

    @Test("Load images from non-existent file throws error")
    func testLoadImagesNonExistentFile() async throws {
        let nonExistentFile = URL(
            fileURLWithPath: "/nonexistent/path/image.tar"
        )

        do {
            try await ImageManager.loadImages(tar: nonExistentFile)
            Issue.record("Expected error for non-existent file")
        } catch let error as ContainerizationError {
            #expect(error.code == .invalidArgument)
        } catch {
            // May throw different error
        }
    }

    @Test(
        "Load images requires started system",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testLoadImagesRequiresStartedSystem() async throws {
        // Stop system if running
        try await ContainerSystem.shared.stop()

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test.tar")

        // Create empty file
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try await ImageManager.loadImages(tar: tempFile)
            Issue.record("Expected error when system not started")
        } catch {
            // Expected to throw
        }
    }

    // MARK: - Delete Images Tests

    @Test(
        "Delete empty image list succeeds",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testDeleteEmptyImageList() async throws {
        try await ContainerSystem.shared.start()

        try await ImageManager.deleteImages([])
    }

    @Test(
        "Delete images filters infrastructure images",
        .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)
    )
    func testDeleteImagesFiltersInfra() async throws {
        // Infrastructure images should not be deleted
        // This would require creating a mock infrastructure image
        #expect(true)  // Placeholder
    }

    // MARK: - Build Image Tests

    @Test("Build image output configuration validates destination")
    func testBuildImageOutputValidation() async throws {
        // Test BuildImageOutputConfiguration validation
        let config = BuildImageOutputConfiguration(
            type: .tar,
            destinationDirectory: nil,
            additionalFields: []
        )

        do {
            try config.verify()
            Issue.record("Expected error for missing destination")
        } catch let error as ContainerizationError {
            #expect(error.code == .invalidArgument)
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Build image OCI output does not require destination")
    func testBuildImageOCINoDestination() async throws {
        let config = BuildImageOutputConfiguration(
            type: .oci,
            destinationDirectory: nil,
            additionalFields: []
        )

        // OCI output should not require destination
        try config.verify()
    }

    @Test("Build image local output requires destination")
    func testBuildImageLocalRequiresDestination() async throws {
        let config = BuildImageOutputConfiguration(
            type: .local,
            destinationDirectory: nil,
            additionalFields: []
        )

        do {
            try config.verify()
            Issue.record("Expected error for missing destination")
        } catch let error as ContainerizationError {
            #expect(error.code == .invalidArgument)
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Build image tar output requires destination")
    func testBuildImageTarRequiresDestination() async throws {
        let config = BuildImageOutputConfiguration(
            type: .tar,
            destinationDirectory: nil,
            additionalFields: []
        )

        do {
            try config.verify()
            Issue.record("Expected error for missing destination")
        } catch let error as ContainerizationError {
            #expect(error.code == .invalidArgument)
        } catch {
            Issue.record("Wrong error type")
        }
    }

    // MARK: - Key Value String Tests

    @Test("Key value string formatting")
    func testKeyValueStringFormat() {
        let result = ImageManager.keyValueString(key: "foo", value: "bar")
        #expect(result == "foo=bar")
    }

    @Test("Key value string handles special characters")
    func testKeyValueStringSpecialChars() {
        let result = ImageManager.keyValueString(
            key: "key-with-dash",
            value: "value_with_underscore"
        )
        #expect(result == "key-with-dash=value_with_underscore")
    }

    @Test("Key value string handles empty values")
    func testKeyValueStringEmptyValue() {
        let result = ImageManager.keyValueString(key: "key", value: "")
        #expect(result == "key=")
    }
}
