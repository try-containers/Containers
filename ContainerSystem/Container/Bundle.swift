//
//  Bundle.swift
//  Containers
//
//  Container bundle that wraps an OCI bundle with container-specific configuration.
//  Stores kernel, init filesystem, container rootfs, and configuration on disk.
//

import Foundation
import Containerization
import ContainerizationError

/// A container bundle that manages on-disk storage for a container's configuration,
/// kernel, init filesystem, and root filesystem.
public struct Bundle: Sendable {
    
    /// The root path of this bundle on disk.
    public let path: URL
    
    // Filenames for bundle contents
    private static let configFilename = "container-config.json"
    private static let kernelFilename = "kernel.json"
    private static let initFsFilename = "init-fs.json"
    private static let rootFsFilename = "rootfs.json"
    
    /// Load an existing bundle from the given path.
    public init(path: URL) {
        self.path = path
    }
    
    /// Load the container configuration from disk.
    public var configuration: ContainerConfiguration {
        get throws {
            try load(filename: Self.configFilename)
        }
    }
    
    /// Load the kernel configuration from disk.
    public var kernel: Kernel {
        get throws {
            try load(filename: Self.kernelFilename)
        }
    }
    
    /// Load the initial filesystem configuration from disk.
    public var initialFilesystem: Filesystem {
        get throws {
            try load(filename: Self.initFsFilename)
        }
    }
    
    /// Load the container root filesystem configuration from disk.
    public var containerRootfs: Filesystem {
        get throws {
            try load(filename: Self.rootFsFilename)
        }
    }
    
    /// Create a new container bundle at the given path.
    public static func create(
        path: URL,
        initialFilesystem: Filesystem,
        kernel: Kernel,
        containerConfiguration: ContainerConfiguration
    ) throws -> Bundle {
        let fm = FileManager.default
        
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
        
        let bundle = Bundle(path: path)
        
        try bundle.write(filename: configFilename, value: containerConfiguration)
        try bundle.write(filename: kernelFilename, value: kernel)
        try bundle.write(filename: initFsFilename, value: initialFilesystem)
        
        return bundle
    }
    
    /// Set the container root filesystem by cloning a source filesystem.
    public func setContainerRootFs(cloning source: Filesystem) throws {
        // Clone the source filesystem image to our bundle directory
        let clonedSource = path.appendingPathComponent("rootfs.img").path
        
        try FileManager.default.copyItem(
            atPath: source.source,
            toPath: clonedSource
        )
        
        // Create a block filesystem pointing to the cloned image
        let rootFs = Filesystem(
            type: .block(format: "ext4"),
            source: clonedSource,
            destination: "/",
            options: []
        )
        
        try write(filename: Self.rootFsFilename, value: rootFs)
    }
    
    /// Persist an updated container configuration to disk.
    public func setConfiguration(_ configuration: ContainerConfiguration) throws {
        try write(filename: Self.configFilename, value: configuration)
    }
    
    /// Delete this bundle and all its contents from disk.
    public func delete() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path.path) {
            try fm.removeItem(at: path)
        }
    }
    
    /// Write a Codable value to a file in the bundle.
    public func write<T: Codable>(filename: String, value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        
        let data = try encoder.encode(value)
        let file = path.appendingPathComponent(filename)
        try data.write(to: file)
    }
    
    /// Load a Codable value from a file in the bundle.
    public func load<T: Codable>(filename: String) throws -> T {
        let file = path.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ContainerizationError(.notFound, message: "bundle file not found: \(filename)")
        }
        
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
