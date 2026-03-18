//
//  ImagesService.swift
//  Containers
//
//  In-process image management service wrapping ImageStore and EXT4Unpacker.
//
//  Created by Axel on 17/3/26.
//

import Foundation
import Containerization
import ContainerizationError
import ContainerizationOCI
import ContainerizationExtras
import ContainerizationOS
import Logging

/// A service that manages container images, wrapping ImageStore and EXT4Unpacker.
public actor ImagesService {

    private let imageStore: ImageStore
    private let contentStore: ContentStore
    private let snapshotsPath: URL
    private let log: Logger

    public init(
        contentStore: ContentStore,
        imageStore: ImageStore,
        snapshotsPath: URL,
        log: Logger
    ) throws {
        self.contentStore = contentStore
        self.imageStore = imageStore
        self.snapshotsPath = snapshotsPath
        self.log = log

        try FileManager.default.createDirectory(at: snapshotsPath, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// List all images in the store.
    public func list() async throws -> [ImageDescription] {
        let images = try await imageStore.list()
        return images.map { $0.description }
    }

    /// Pull an image from a remote registry.
    public func pull(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication? = nil,
        progressUpdate: ProgressHandler?
    ) async throws -> ImageDescription {
        // Try provided auth first, then keychain, then environment variables
        let resolvedAuth = auth ?? resolveAuthentication(for: reference)
        
        let image = try await imageStore.pull(
            reference: reference,
            platform: platform,
            insecure: insecure,
            auth: resolvedAuth,
            progress: progressUpdate
        )
        return image.description
    }

    /// Unpack an image to an EXT4 block device for use as a container rootfs.
    public func unpack(
        description: ImageDescription,
        platform: Platform?,
        progressUpdate: ProgressHandler?
    ) async throws {
        let image = try await imageStore.get(reference: description.reference)
        let targetPlatform = platform ?? .current

        // Determine the EXT4 file path for this image+platform combination
        let ext4Path = snapshotFilePath(for: description, platform: targetPlatform)

        // Skip if already unpacked
        if FileManager.default.fileExists(atPath: ext4Path.path) {
            return
        }

        let unpacker = EXT4Unpacker(blockSizeInBytes: 10 * 1024 * 1024 * 1024)
        _ = try await unpacker.unpack(image, for: targetPlatform, at: ext4Path, progress: progressUpdate)
    }

    /// Get a Filesystem representing the unpacked image snapshot.
    public func getImageSnapshot(description: ImageDescription, platform: Platform) async throws -> Filesystem {
        let ext4Path = snapshotFilePath(for: description, platform: platform)

        guard FileManager.default.fileExists(atPath: ext4Path.path) else {
            throw ContainerizationError(.notFound, message: "image snapshot not found at \(ext4Path.path). Was the image unpacked?")
        }

        return Filesystem(
            type: .block(format: "ext4"),
            source: ext4Path.path,
            destination: "/",
            options: []
        )
    }

    /// Load images from an OCI layout directory on disk.
    public func load(
        from directory: URL,
        force: Bool = false
    ) async throws -> ([ImageDescription], [String]) {
        let images = try await imageStore.load(from: directory)
        let descriptions = images.map { $0.description }
        let references = descriptions.map { $0.reference }
        return (descriptions, references)
    }

    /// Tag an image with a new reference.
    public func tag(existing: String, new: String) async throws -> ImageDescription {
        let image = try await imageStore.tag(existing: existing, new: new)
        return image.description
    }

    /// Save images to an OCI layout directory.
    public func save(references: [String], out: URL, platform: Platform?) async throws {
        try await imageStore.save(references: references, out: out, platform: platform)
    }

    /// Push an image to a remote registry.
    public func push(
        reference: String,
        platform: Platform?,
        insecure: Bool,
        auth: Authentication? = nil,
        progressUpdate: ProgressHandler?
    ) async throws {
        let resolvedAuth = auth ?? resolveAuthentication(for: reference)
        
        try await imageStore.push(
            reference: reference,
            platform: platform,
            insecure: insecure,
            auth: resolvedAuth,
            progress: progressUpdate
        )
    }
    
    /// Delete an image by reference.
    public func delete(reference: String, garbageCollect: Bool = false) async throws {
        try await imageStore.delete(reference: reference, performCleanup: garbageCollect)
    }

    // MARK: - Private Helpers

    private func snapshotFilePath(for description: ImageDescription, platform: Platform) -> URL {
        // Use a stable hash of the digest + platform for the snapshot file name
        let key = "\(description.digest)-\(platform.os)-\(platform.architecture)"
        let fileName = key.replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return snapshotsPath.appendingPathComponent(fileName)
    }
    
    /// Security domain for keychain credential lookups.
    /// Matches the domain used by the `container` CLI.
    private static let keychainDomain = "com.apple.container.registry"
    
    /// Resolve authentication for a registry reference.
    /// Checks environment variables first (for CI), then keychain, then returns nil (anonymous).
    /// This mirrors the auth flow from the Apple container package's ImagesService.
    private func resolveAuthentication(for reference: String) -> Authentication? {
        guard let hostname = Self.extractHostname(from: reference) else {
            return nil
        }
        
        // 1. Check environment variables (highest priority, enables CI/CD)
        let env = ProcessInfo.processInfo.environment
        if env["CONTAINER_REGISTRY_HOST"] == hostname,
           let user = env["CONTAINER_REGISTRY_USER"],
           let token = env["CONTAINER_REGISTRY_TOKEN"] {
            return BasicAuthentication(username: user, password: token)
        }
        
        // 2. Check macOS Keychain (credentials stored via `container registry login`)
        let keychain = KeychainHelper(securityDomain: Self.keychainDomain)
        if let keychainAuth = try? keychain.lookup(hostname: hostname) {
            return keychainAuth
        }
        
        // 3. No credentials found — return nil for anonymous access.
        // The RegistryClient handles the 401 → Bearer token exchange for public images.
        return nil
    }
    
    /// Extract the registry hostname from an image reference.
    private static func extractHostname(from reference: String) -> String? {
        guard let parsed = try? ContainerizationOCI.Reference.parse(reference) else {
            return nil
        }
        return parsed.resolvedDomain
    }
}
