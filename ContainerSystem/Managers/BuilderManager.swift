//
//  BuilderManager.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//
import Foundation
import Observation
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import ContainerizationOS
import Logging

/// Manages BuildKit builder container for building images.
/// Create instances via public init() - automatically references shared runtime.
@Observable
@MainActor
public final class BuilderManager {
    
    /// Internal runtime reference (hidden from UI)
    internal let runtime: ContainerRuntime
    private let logger: Logger
    
    public static let buildkitContainerId = "buildkit"
    
    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        var logger = Logger(label: "app.containers.manager.builder")
        logger.logLevel = .info
        self.logger = logger
    }
    
    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    internal init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        var logger = Logger(label: "app.containers.manager.builder.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif
    
    // MARK: - Public API
    
    /// Start the BuildKit builder container
    /// Start the BuildKit builder container
    /// This method is idempotent - if builder is already running, it will restart it to ensure fresh mounts
    public func start(cpus: Int64 = 2, memory: UInt64 = 1024.mib()) async throws {
        logger.info("Starting builder with cpus=\(cpus), memory=\(memory)")

        let containersService = try await runtime.getContainersService()
        let imagesService = try await runtime.getImagesService()
        let kernelService = try await runtime.getKernelService()
        let appRoot = try runtime.getAppRoot()

        let builderImage: String = DefaultsStore.get(key: .defaultBuilderImage)
        let exportsMount: String = appRoot.appendingPathComponent(
            ".build"
        ).path

        if !FileManager.default.fileExists(atPath: exportsMount) {
            try FileManager.default.createDirectory(
                atPath: exportsMount,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        // Content store path needs to be accessible by builder for image operations
        let imagesPath = appRoot.appendingPathComponent("images").path
        
        // BuildKit data directory - needs to be persistent and support mmap for BoltDB
        let buildkitDataPath = appRoot.appendingPathComponent("buildkit-data").path
        
        // Check if BoltDB database exists and might be corrupted
        // If BuildKit previously crashed, the database can be in a bad state
        let workerDbPath = (buildkitDataPath as NSString).appendingPathComponent("worker.db")
        if FileManager.default.fileExists(atPath: workerDbPath) {
            logger.info("Found existing BuildKit database, checking if it needs cleanup")
            // For now, always delete and recreate to avoid corruption issues
            // In the future, we could try to validate the database first
            try? FileManager.default.removeItem(atPath: buildkitDataPath)
            logger.info("Cleaned up BuildKit data directory")
        }
        
        if !FileManager.default.fileExists(atPath: buildkitDataPath) {
            try FileManager.default.createDirectory(
                atPath: buildkitDataPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let builderPlatform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

        // Check if builder container already exists
        let containerList = await containersService.list()
        let existingContainer = containerList.first(where: { $0.configuration.id == Self.buildkitContainerId })

        if let existingContainer {
            logger.info("Found existing builder container, cleaning it up to ensure fresh start")
            // Always delete existing builder to ensure we start with clean tmpfs mount
            // This avoids BoltDB corruption issues
            switch existingContainer.status {
            case .running:
                try await containersService.stop(id: Self.buildkitContainerId, options: .default)
                try await containersService.delete(id: Self.buildkitContainerId)
            case .stopped:
                try await containersService.delete(id: Self.buildkitContainerId)
            case .stopping:
                throw ContainerizationError(
                    .invalidState,
                    message: "builder is stopping, please wait until it is fully stopped before proceeding"
                )
            case .unknown:
                try? await containersService.delete(id: Self.buildkitContainerId)
            }
        }

        let shimArguments: [String] = [
            "--debug",
            "--vsock",
        ]

        try validEntityName(Self.buildkitContainerId)

        let processConfig = ProcessConfiguration(
            executable: "/usr/local/bin/container-builder-shim",
            arguments: shimArguments,
            environment: [],
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0)
        )

        var resources = ContainerConfiguration.Resources()
        resources.cpus = Int(cpus)
        resources.memoryInBytes = memory

        logger.info("Pulling builder image: \(builderImage)")

        let imageDescription = try await imagesService.pull(
            reference: builderImage,
            platform: builderPlatform,
            insecure: false,
            progressUpdate: { _ in }
        )

        logger.info("Unpacking builder image")
        try await imagesService.unpack(
            description: imageDescription,
            platform: builderPlatform,
            progressUpdate: { _ in }
        )

        var config = ContainerConfiguration(id: Self.buildkitContainerId, image: imageDescription, process: processConfig)
        config.resources = resources
        config.mounts = [
            .init(
                type: .tmpfs,
                source: "",
                destination: "/run",
                options: []
            ),
            .init(
                type: .virtiofs,
                source: exportsMount,
                destination: "/var/lib/container-builder-shim/exports",
                options: []
            ),
            .init(
                type: .virtiofs,
                source: imagesPath,
                destination: imagesPath,
                options: []
            ),
            // Use tmpfs for BuildKit data directory because virtiofs doesn't support mmap
            // which BoltDB requires. This means BuildKit state is ephemeral (lost on restart)
            // but that's acceptable for a build cache.
            // However, we need BuildKit to be able to access our content store for images
            .init(
                type: .tmpfs,
                source: "",
                destination: "/var/lib/buildkit",
                options: []
            ),
        ]
        // Enable Rosetta only if the user didn't ask to disable it
        config.rosetta = DefaultsStore.getBool(key: .buildRosetta) ?? true

        // Attach to default network (sandboxed mode uses built-in NAT networking with automatic DNS)
        let defaultNetworkName = "default"
        config.networks = [AttachmentConfiguration(network: defaultNetworkName, options: AttachmentOptions(hostname: Self.buildkitContainerId))]

        logger.info("Getting kernel")
        let kernel = try await kernelService.getDefaultKernel(platform: .current)

        logger.info("Creating BuildKit container")
        let options = ContainerCreateOptions(autoRemove: false)
        try await containersService.create(configuration: config, kernel: kernel, options: options)

        try await startBuildKitProcess(service: containersService)

        logger.info("Builder started successfully")
    }
    
    /// Restart the builder container to pick up fresh virtiofs mounts
    /// This is necessary when new subdirectories have been created in mounted paths
    /// because virtiofs in sandboxed apps doesn't dynamically show new subdirectories
    public func restart(cpus: Int64 = 2, memory: UInt64 = 1024.mib()) async throws {
        logger.info("Restarting builder to pick up fresh mounts")
        
        let containersService = try await runtime.getContainersService()
        
        // Stop the existing builder
        let containerList = await containersService.list()
        let existingContainer = containerList.first(where: { $0.configuration.id == Self.buildkitContainerId })
        
        if let existingContainer {
            switch existingContainer.status {
            case .running:
                logger.info("Stopping existing builder")
                try await containersService.stop(id: Self.buildkitContainerId, options: .default)
                try await containersService.delete(id: Self.buildkitContainerId)
            case .stopped:
                logger.info("Deleting stopped builder")
                try await containersService.delete(id: Self.buildkitContainerId)
            case .stopping:
                throw ContainerizationError(
                    .invalidState,
                    message: "builder is stopping, please wait until it is fully stopped before proceeding"
                )
            case .unknown:
                try? await containersService.delete(id: Self.buildkitContainerId)
            }
        }
        
        // Start a fresh builder with the new mounts
        try await start(cpus: cpus, memory: memory)
    }
    
    // MARK: - Private Methods
    
    /// Validate that a name is a valid entity name.
    @discardableResult
    public func validEntityName(_ name: String) throws -> Bool {
        guard !name.isEmpty, name.count <= 255 else {
            throw ContainerizationError(.invalidArgument, message: "invalid entity name '\(name)': must be between 1 and 255 characters")
        }
        
        let entityNamePattern = "^[A-Za-z0-9][A-Za-z0-9_.-]*$"
        let regex = try NSRegularExpression(pattern: entityNamePattern)
        let range = NSRange(name.startIndex..., in: name)
        
        guard regex.firstMatch(in: name, range: range) != nil else {
            throw ContainerizationError(.invalidArgument, message: "invalid entity name '\(name)': must match \(entityNamePattern)")
        }
        
        return true
    }
    
    private func startBuildKitProcess(service: ContainersService) async throws {
        do {
            logger.info("Bootstrapping BuildKit container")
            
            // Create pipes to capture BuildKit's stdout/stderr for debugging
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            
            try await service.bootstrap(id: Self.buildkitContainerId, stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting])

            logger.info("Starting BuildKit process")
            
            // Start a task to read and log BuildKit output
            Task {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    self.logger.info("BuildKit stdout: \(line)")
                }
            }
            Task {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    self.logger.error("BuildKit stderr: \(line)")
                }
            }
            
            try await service.startProcess(id: Self.buildkitContainerId, processID: Self.buildkitContainerId)

            logger.info("BuildKit process started successfully")
        } catch {
            logger.error("Failed to start BuildKit: \(error)")
            try? await service.stop(id: Self.buildkitContainerId, options: .default)
            try? await service.delete(id: Self.buildkitContainerId)
            if error is ContainerizationError {
                throw error
            }
            throw ContainerizationError(.internalError, message: "failed to start BuildKit: \(error)")
        }
    }
}
