//
//  ContainerManager.swift
//  Containers
//
//  Manager for container operations - wraps SandboxedContainersService
//  Architecture: Actor singleton that gets services from ContainerSystem
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation
import ContainerAPIClient
import ContainerAPIService
import ContainerImagesService
import ContainerizationError
import ContainerizationOS
import ArgumentParser
import ContainerPersistence
import ContainerNetworkService
import Containerization
import ContainerizationOCI
import ContainerResource
import Logging

/// Manages container operations.
/// Create instances via public init() - automatically references shared runtime.
@Observable
@MainActor
public final class ContainerManager {
    
    /// Internal runtime reference (hidden from UI)
    internal let runtime: ContainerRuntime
    private let logger: Logger
    
    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        var logger = Logger(label: "app.containers.manager.containers")
        logger.logLevel = .info
        self.logger = logger
    }
    
    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    internal init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        var logger = Logger(label: "app.containers.manager.containers.test")
        logger.logLevel = .debug
        self.logger = logger
    }
    #endif
    
    // MARK: - Public API (similar to Apple's ClientContainer static methods)
    
    public func create(
        imageReference: String,
        imagesDir: URL,
        arguments: [KeyValue],
        process: ContainerProcess,
        container: ContainerInfo,
        resource: ContainerConfiguration.Resources,
        registryScheme: String = RequestScheme.auto.rawValue
    ) async throws {
        let service = try await runtime.getContainersService()

        let id = Self.createContainerID(name: container.name)
        try Self.validEntityName(id)
        
        logger.info("Creating container: \(id)")

        let (configuration, kernel) = try await createContainerConfig(
            imageReference: imageReference,
            imagesDir: imagesDir,
            arguments: arguments.map { "\($0.key)=\($0.value)" },
            process: process,
            container: container,
            resource: resource,
            registryScheme: registryScheme
        )

        let options = ContainerCreateOptions(
            autoRemove: container.deleteOnTermination
        )
        
        try await service.create(configuration: configuration, kernel: kernel, options: options)

        if !container.cidfile.isEmpty {
            try writeCIDFile(path: container.cidfile, id: configuration.id)
        }
        
        logger.info("Container created: \(configuration.id)")
    }
   
    public func start(id: String, attachStdout: Bool = false, attachStdin: Bool = false) async throws {
        let service = try await runtime.getContainersService()
        
        logger.info("Starting container: \(id)")
        
        do {
            try await service.bootstrap(id: id, stdio: [nil, nil, nil])
            try await service.startProcess(id: id, processID: id)
            logger.info("Container started: \(id)")
        } catch {
            try? await service.stop(id: id, options: .default)
            
            if error is ContainerizationError {
                throw error
            }
            
            throw ContainerizationError(.internalError, message: "failed to start container: \(error)")
        }
    }

    public func list() async throws -> [ContainerSnapshot] {
        let service = try await runtime.getContainersService()
        
        return await service.list()
    }
    
    public func get(id: String) async throws -> ContainerSnapshot {
        let service = try await runtime.getContainersService()
        
        let snapshots = await service.list()
        
        guard let snapshot = snapshots.first(where: { $0.configuration.id == id }) else {
            throw ContainerizationError(.notFound, message: "Container not found: \(id)")
        }
        
        return snapshot
    }
    
    public func exec(id: String, arguments: [String]) async throws -> String {
        let service = try await runtime.getContainersService()
        
        logger.info("Executing command in container: \(id)")
        return try await service.exec(id: id, arguments: arguments)
    }

    public func getLog(id: String, containerDir: URL, boot: Bool) async throws -> String {
        let logFile = containerDir.appendingPathComponent(boot ? "vminitd.log" : "stdio.log")
        guard let handle = try? FileHandle(forReadingFrom: logFile),
              let data = try? handle.readToEnd(),
              let logs = String(data: data, encoding: .utf8) else {
            return ""
        }
        try? handle.close()
        
        return logs.trimmingCharacters(in: .newlines)
    }
    
    public func stop(snapshots: [ContainerSnapshot], timeoutSeconds: Int32) async throws {
        let service = try await runtime.getContainersService()
        
        logger.info("Stopping \(snapshots.count) container(s)")

        let stopOptions = ContainerStopOptions(
            timeoutInSeconds: timeoutSeconds,
            signal: SIGTERM
        )

        var failed: [(String, Error)] = []
        
        for container in snapshots {
            do {
                try await service.stop(id: container.configuration.id, options: stopOptions)
                logger.info("Stopped container: \(container.configuration.id)")
            } catch {
                logger.error("Failed to stop container \(container.configuration.id): \(error)")
                failed.append((container.configuration.id, error))
            }
        }

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message: "Failed to stop one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }
    
    public func delete(snapshots: [ContainerSnapshot], force: Bool) async throws {
        let service = try await runtime.getContainersService()
        
        logger.info("Deleting \(snapshots.count) container(s)")

        var failed: [(String, Error)] = []
        
        for container in snapshots {
            do {
                if container.status == .running && !force {
                    throw ContainerizationError(.invalidState, message: "container: \(container.configuration.id) is running")
                }
                
                if container.status == .running && force {
                    try await service.stop(id: container.configuration.id, options: .default)
                }

                try await service.delete(id: container.configuration.id)
                logger.info("Container deleted: \(container.configuration.id)")
            } catch {
                logger.error("Failed to delete container \(container.configuration.id): \(error)")
                failed.append((container.configuration.id, error))
            }
        }

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message: "Failed to delete one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func writeCIDFile(path: String, id: String) throws {
        let data = id.data(using: .utf8)
        var attributes = [FileAttributeKey: Any]()
        attributes[.posixPermissions] = 0o644
        
        let success = FileManager.default.createFile(
            atPath: path,
            contents: data,
            attributes: attributes
        )
        
        guard success else {
            throw ContainerizationError(.internalError, message: "failed to create cidfile at \(path): \(errno)")
        }
    }
    
    /// Split a shell-like command string into components, respecting double and single quotes.
    private static func shellSplit(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false

        for ch in command {
            if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == " " && !inDouble && !inSingle {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func createContainerID(name: String?) -> String {
        guard let name, !name.isEmpty else {
            return UUID().uuidString.lowercased()
        }
        return name
    }

    private static func validEntityName(_ name: String) throws {
        let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9_.-]+$"#
        let regex = try Regex(pattern)
        if try regex.firstMatch(in: name) == nil {
            throw ContainerizationError(.invalidArgument, message: "invalid entity name \(name)")
        }
    }

    private func resolveImage(
        reference: String,
        platform: Platform,
        insecure: Bool,
        imagesService: ImagesService
    ) async throws -> ImageDescription {
        let existingImages = try await imagesService.list()
        if let existing = existingImages.first(where: { $0.reference == reference }) {
            logger.info("Using existing image: \(existing.reference)")
            try await imagesService.unpack(
                description: existing,
                platform: platform,
                progressUpdate: { _ in }
            )
            return existing
        }

        logger.info("Pulling image: \(reference)")
        let imageDescription = try await imagesService.pull(
            reference: reference,
            platform: platform,
            insecure: insecure,
            progressUpdate: { events in
                for event in events {
                    if case .setDescription(let desc) = event {
                        self.logger.info("\(desc)")
                    }
                }
            }
        )

        logger.info("Unpacking image")
        try await imagesService.unpack(
            description: imageDescription,
            platform: platform,
            progressUpdate: { _ in }
        )

        return imageDescription
    }
    
    private func createContainerConfig(
        imageReference: String,
        imagesDir: URL,
        arguments: [String],
        process: ContainerProcess,
        container: ContainerInfo,
        resource: ContainerConfiguration.Resources,
        registryScheme: String
    ) async throws -> (ContainerConfiguration, Kernel) {
        let id = Self.createContainerID(name: container.name)
        try Self.validEntityName(id)

        var requestedPlatform = Parser.platform(os: container.os, arch: container.arch)
        
        if let platform = container.platform {
            requestedPlatform = try Parser.platform(from: platform)
        }
        
        let scheme = try RequestScheme(registryScheme)
        let insecure = scheme == .http
        
        // Normalize image reference to handle short names like "alpine:latest"
        let processedReference = try ClientImage.normalizeReference(imageReference)
        
        let imagesService = try await runtime.getImagesService()
        
        // Resolve image - check local first, then pull if needed
        logger.info("Resolving image: \(processedReference)")
        
        let imageDescription = try await resolveImage(
            reference: processedReference,
            platform: requestedPlatform,
            insecure: insecure,
            imagesService: imagesService
        )
        
        logger.info("Fetching kernel")
        
        let kernel = try await getKernel(container: container)

        logger.info("Fetching init image")
        
        let initImageDescription = try await imagesService.pull(
            reference: ClientImage.initImageRef,
            platform: .current,
            insecure: insecure,
            progressUpdate: { _ in }
        )

        logger.info("Unpacking init image")
        
        try await imagesService.unpack(
            description: initImageDescription,
            platform: requestedPlatform,
            progressUpdate: { events in
                Task { @MainActor in
                    // ContainerSystem.shared.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                }
            }
        )

        // Get image config - we need to use the lower level ImageStore for this
        // since ImagesService doesn't expose config fetching
        let imageStore = try ImageStore(path: imagesDir)
        let image = try await imageStore.get(reference: imageDescription.reference)
        let imageConfig = try await image.config(for: requestedPlatform).config
        let pc = try Self.parseProcessConfiguration(
            arguments: arguments,
            process: process,
            container: container,
            config: imageConfig
        )

        var config = ContainerConfiguration(id: id, image: imageDescription, process: pc)
        config.platform = requestedPlatform
        config.resources = resource

        let resolvedMounts: [Filesystem] = container.virtualFileSystem + container.temporaryFileSystem + container.volumes

        config.mounts = resolvedMounts
        config.virtualization = container.virtualization
        config.networks = try Self.getAttachmentConfigurations(containerId: config.id, networkIds: container.networks)
        
        // Note: Sandboxed service uses built-in NAT networking, no validation needed

        if container.dnsDisabled {
            config.dns = nil
        } else {
            let domain: String? = container.dnsDomain ?? DefaultsStore.getOptional(key: .defaultDNSDomain)
            let dnsConfig = ContainerConfiguration.DNSConfiguration(
                nameservers: container.dnsNameservers,
                domain: domain,
                searchDomains: container.dnsSearchDomains,
                options: container.dnsOptions
            )
            config.dns = dnsConfig
        }

        if Platform.current.architecture == "arm64" && requestedPlatform.architecture == "amd64" {
            config.rosetta = true
        }

        config.labels = container.labels
        config.publishedPorts = container.publishPorts
        config.publishedSockets = container.publishSockets
        config.ssh = container.ssh

        return (config, kernel)
    }

    private static func getAttachmentConfigurations(containerId: String, networkIds: [String]) throws -> [AttachmentConfiguration] {
        // make an FQDN for the first interface
        let fqdn: String?
        if !containerId.contains(".") {
            // add default domain if it exists, and container ID is unqualified
            if let dnsDomain = DefaultsStore.getOptional(key: .defaultDNSDomain) {
                fqdn = "\(containerId).\(dnsDomain)."
            } else {
                fqdn = nil
            }
        } else {
            // use container ID directly if fully qualified
            fqdn = "\(containerId)."
        }

        guard networkIds.isEmpty else {
            // networks may only be specified for macOS 26+
            guard #available(macOS 26, *) else {
                throw ContainerizationError(.invalidArgument, message: "non-default network configuration requires macOS 26 or newer")
            }

            // attach the first network using the fqdn, and the rest using just the container ID
            return networkIds.enumerated().map { item in
                guard item.offset == 0 else {
                    return AttachmentConfiguration(network: item.element, options: AttachmentOptions(hostname: containerId))
                }
                return AttachmentConfiguration(network: item.element, options: AttachmentOptions(hostname: fqdn ?? containerId))
            }
        }
        // if no networks specified, attach to the default network
        return [AttachmentConfiguration(network: ClientNetwork.defaultNetworkName, options: AttachmentOptions(hostname: fqdn ?? containerId))]
    }

    private func getKernel(container: ContainerInfo) async throws -> Kernel {
        let kernelService = try await runtime.getKernelService()
        
        // For the image itself we'll take the user input and try with it as we can do userspace
        // emulation for x86, but for the kernel we need it to match the hosts architecture.
        let s: SystemPlatform = .current
        if let userKernel = container.kernel {
            guard FileManager.default.fileExists(atPath: userKernel) else {
                throw ContainerizationError(.notFound, message: "Kernel file not found at path \(userKernel)")
            }
            let p = URL(filePath: userKernel)
            return .init(path: p, platform: s)
        }
        
        return try await kernelService.getDefaultKernel(platform: s)
    }
    
    private static func parseProcessConfiguration(
        arguments: [String],
        process: ContainerProcess,
        container: ContainerInfo,
        config: ContainerizationOCI.ImageConfig?
    ) throws -> ProcessConfiguration {

        let imageEnvVars = config?.env ?? []
        let envvars = try Parser.allEnv(imageEnvs: imageEnvVars, envFiles: process.envFile, envs: process.environments)

        let workingDir: String = {
            if let cwd = process.workingDirectory {
                return cwd
            }
            if let cwd = config?.workingDir {
                return cwd
            }
            return "/"
        }()

        let processArguments: [String]? = {
            var result: [String] = []
            var hasEntrypointOverride: Bool = false
            
            // ensure the entrypoint is honored if it has been explicitly set by the user
            if let entrypoint = container.entryPoint, !entrypoint.isEmpty {
                // Split the entrypoint string into executable + arguments,
                // respecting quoted substrings (e.g. sh -c "echo hello" → ["sh", "-c", "echo hello"])
                result = Self.shellSplit(entrypoint)
                hasEntrypointOverride = true
            } else if let entrypoint = config?.entrypoint, !entrypoint.isEmpty {
                result = entrypoint
            }
            
            if !arguments.isEmpty {
                result.append(contentsOf: arguments)
            } else {
                if let cmd = config?.cmd, !hasEntrypointOverride, !cmd.isEmpty {
                    result.append(contentsOf: cmd)
                }
            }
            
            return result.count > 0 ? result : nil
        }()

        guard let commandToRun = processArguments, commandToRun.count > 0 else {
            throw ContainerizationError(.invalidArgument, message: "Command/Entrypoint not specified for container process")
        }

        let defaultUser: ProcessConfiguration.User = {
            if let u = config?.user {
                return .raw(userString: u)
            }
            return .id(uid: 0, gid: 0)
        }()

        let (user, additionalGroups) = Parser.user(
            user: process.user, uid: process.uid,
            gid: process.gid, defaultUser: defaultUser)

        return .init(
            executable: commandToRun.first!,
            arguments: [String](commandToRun.dropFirst()),
            environment: envvars,
            workingDirectory: workingDir,
            terminal: process.tty,
            user: user,
            supplementalGroups: additionalGroups
        )
    }

}
