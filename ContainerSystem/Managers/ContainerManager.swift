//
//  ContainerManager.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import Foundation
import ContainerizationError
import ContainerizationOS
import Containerization
import ContainerizationOCI
import Logging

/// Manages container operations.
/// Create instances via public init() - automatically references shared runtime.
@Observable
@MainActor
public final class ContainerManager {
    
    /// Internal runtime reference (hidden from UI)
    internal let runtime: ContainerRuntime
    private let logger: Logger
    
    /// Observable property that triggers UI updates when containers change
    /// This mirrors the runtime's lastContainerStateChange property
    public var lastContainerChange: Date {
        runtime.lastContainerStateChange
    }
    
    /// Observable property for progress messages during long-running operations
    /// This mirrors the runtime's progressMessage property
    public var progressMessage: String {
        runtime.progressMessage
    }
    
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
    
    // MARK: - Public API
    
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
        let containerID = try Self.createContainerID(name: container.name)
        let existingContainers = await service.list()
        guard !existingContainers.contains(where: { $0.configuration.id == containerID }) else {
            throw ContainerizationError(.exists, message: "container already exists: \(containerID)")
        }

        let (configuration, kernel) = try await createContainerConfig(
            id: containerID,
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
    }
   
    public func start(id: String, attachStdout: Bool = false, attachStdin: Bool = false) async throws {
        let service = try await runtime.getContainersService()
        
        do {
            try await service.bootstrap(id: id, stdio: [nil, nil, nil])
            try await service.startProcess(id: id, processID: id)
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
    
    public func stop(ids: [String], timeoutSeconds: Int32) async throws {
        let service = try await runtime.getContainersService()

        let stopOptions = ContainerStopOptions(
            timeoutInSeconds: timeoutSeconds,
            signal: SIGTERM
        )

        var failed: [(String, Error)] = []
        
        for id in ids {
            do {
                try await service.stop(id: id, options: stopOptions)
            } catch {
                logger.error("Failed to stop container \(id): \(error)")
                failed.append((id, error))
            }
        }

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message: "Failed to stop one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }

    public func stop(snapshots: [ContainerSnapshot], timeoutSeconds: Int32) async throws {
        try await stop(ids: snapshots.map(\.configuration.id), timeoutSeconds: timeoutSeconds)
    }
    
    public func mountVolume(containerID: String, volume: Volume, destination: String) async throws {
        let service = try await runtime.getContainersService()
        let snapshots = await service.list()
        
        guard let snapshot = snapshots.first(where: { $0.configuration.id == containerID }) else {
            throw ContainerizationError(.notFound, message: "Container not found: \(containerID)")
        }
        
        guard snapshot.status == .stopped else {
            throw ContainerizationError(.invalidState, message: "container must be stopped before changing volume mounts")
        }
        
        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDestination.hasPrefix("/") else {
            throw ContainerizationError(.invalidArgument, message: "Volume mount path must be an absolute container path")
        }
        
        var mounts = snapshot.configuration.mounts
        guard !mounts.contains(where: { $0.destination == trimmedDestination }) else {
            throw ContainerizationError(.exists, message: "a mount already exists at \(trimmedDestination)")
        }
        
        mounts.append(
            Filesystem.volume(
                name: volume.name,
                format: volume.format,
                source: volume.source,
                destination: trimmedDestination
            )
        )
        
        try await service.updateMounts(id: containerID, mounts: mounts)
    }
    
    public func delete(ids: [String], force: Bool) async throws {
        let service = try await runtime.getContainersService()
        let snapshots = await service.list()

        var failed: [(String, Error)] = []
        
        for id in ids {
            do {
                guard let container = snapshots.first(where: { $0.configuration.id == id }) else {
                    throw ContainerizationError(.notFound, message: "Container not found: \(id)")
                }

                if container.status == .running && !force {
                    throw ContainerizationError(.invalidState, message: "container: \(id) is running")
                }
                
                if container.status == .running && force {
                    try await service.stop(id: id, options: .default)
                }

                try await service.delete(id: id)
            } catch {
                logger.error("Failed to delete container \(id): \(error)")
                failed.append((id, error))
            }
        }

        if !failed.isEmpty {
            throw ContainerizationError(
                .internalError,
                message: "Failed to delete one or more containers: \n\(failed.map({"\($0.0): \($0.1)"}).joined(separator: "\n"))"
            )
        }
    }

    public func delete(snapshots: [ContainerSnapshot], force: Bool) async throws {
        try await delete(ids: snapshots.map(\.configuration.id), force: force)
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

    private static func createContainerID(name: String?) throws -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            return UUID().uuidString.lowercased()
        }

        guard isValidContainerName(trimmedName) else {
            throw ContainerizationError(
                .invalidArgument,
                message: "invalid container name '\(trimmedName)': must start with a letter or number and contain only letters, numbers, underscores, periods, and hyphens"
            )
        }

        return trimmedName
    }

    private static func isValidContainerName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        return name.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
    }

    private func resolveImage(
        reference: String,
        platform: Platform,
        insecure: Bool,
        imagesService: ImagesService
    ) async throws -> ImageDescription {
        let existingImages = try await imagesService.list()
        
        // Try exact match first
        if let existing = existingImages.first(where: { $0.reference == reference }) {
            try await imagesService.unpack(
                description: existing,
                platform: platform,
                progressUpdate: { events in
                    Task { @MainActor in
                        self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                    }
                }
            )
            return existing
        }
        
        // Try matching by comparing digests - most reliable
        let matchingByDigest = existingImages.first { image in
            // If the input reference contains a digest, match by digest
            if reference.contains("@sha256:") {
                return image.digest == reference.split(separator: "@").last.map(String.init)
            }
            return false
        }
        
        if let existing = matchingByDigest {
            try await imagesService.unpack(
                description: existing,
                platform: platform,
                progressUpdate: { events in
                    Task { @MainActor in
                        self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                    }
                }
            )
            return existing
        }
        
        // Try matching by parsing the reference to handle different formats
        // e.g., "alpine:latest" should match "docker.io/library/alpine:latest"
        if let parsedRef = try? ContainerizationOCI.Reference.parse(reference) {
            let matchingImage = existingImages.first { image in
                guard let imageRef = try? ContainerizationOCI.Reference.parse(image.reference) else {
                    return false
                }
                
                // Extract just the repository name without registry
                let refNameComponents = parsedRef.name.split(separator: "/")
                let imageNameComponents = imageRef.name.split(separator: "/")
                
                let refShortName = refNameComponents.last ?? Substring(parsedRef.name)
                let imageShortName = imageNameComponents.last ?? Substring(imageRef.name)
                
                // Match on short name and tag
                let nameMatch = refShortName == imageShortName
                let tagMatch = (parsedRef.tag ?? "latest") == (imageRef.tag ?? "latest")
                return nameMatch && tagMatch
            }
            
            if let existing = matchingImage {
                try await imagesService.unpack(
                    description: existing,
                    platform: platform,
                    progressUpdate: { events in
                        Task { @MainActor in
                            self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                        }
                    }
                )
                return existing
            }
        }

        let imageDescription = try await imagesService.pull(
            reference: reference,
            platform: platform,
            insecure: insecure,
            progressUpdate: { events in
                Task { @MainActor in
                    self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                }
            }
        )

        try await imagesService.unpack(
            description: imageDescription,
            platform: platform,
            progressUpdate: { events in
                Task { @MainActor in
                    self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                }
            }
        )

        return imageDescription
    }
    
    private func createContainerConfig(
        id: String,
        imageReference: String,
        imagesDir: URL,
        arguments: [String],
        process: ContainerProcess,
        container: ContainerInfo,
        resource: ContainerConfiguration.Resources,
        registryScheme: String
    ) async throws -> (ContainerConfiguration, Kernel) {
        guard let platform = container.platform else {
            throw ContainerizationError(.invalidArgument, message: "Container platform is not specified")
        }
        
        let scheme = try RequestScheme(registryScheme)
        let insecure = scheme == .http
        
        // Normalize image reference to handle short names like "alpine:latest"
        let processedReference = try ClientImage.normalizeReference(imageReference)
        
        let imagesService = try await runtime.getImagesService()
        
        // Resolve image - check local first, then pull if needed
        let imageDescription = try await resolveImage(
            reference: processedReference,
            platform: platform,
            insecure: insecure,
            imagesService: imagesService
        )
        
        let kernel = try await getKernel(container: container)
        
        let initImageDescription = try await imagesService.pull(
            reference: ClientImage.initImageRef,
            platform: .current,
            insecure: insecure,
            progressUpdate: { events in
                Task { @MainActor in
                    self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                }
            }
        )
        
        try await imagesService.unpack(
            description: initImageDescription,
            platform: platform,
            progressUpdate: { events in
                Task { @MainActor in
                    self.runtime.progressMessage = events.map { String(describing: $0) }.joined(separator: "\n")
                }
            }
        )

        // Get image config - we need to use the lower level ImageStore for this
        // since ImagesService doesn't expose config fetching
        let imageStore = try ImageStore(path: imagesDir)
        let image = try await imageStore.get(reference: imageDescription.reference)
        let imageConfig = try await image.config(for: platform).config
        let pc = try Self.parseProcessConfiguration(
            arguments: arguments,
            process: process,
            container: container,
            config: imageConfig
        )

        var config = ContainerConfiguration(id: id, image: imageDescription, process: pc)
        config.platform = platform
        config.resources = resource
        config.creationDate = Date()
        config.capabilities = container.capabilities
        config.shmSize = container.shmSize
        config.stopSignal = container.stopSignal ?? imageConfig?.stopSignal

        let resolvedMounts: [Filesystem] = container.virtualFileSystem + container.temporaryFileSystem + container.volumes

        config.mounts = resolvedMounts
        config.virtualization = container.virtualization
        config.networks = try Self.getAttachmentConfigurations(containerId: config.id, networkIds: container.networks)
        
        // Note: Sandboxed service uses built-in NAT networking, no validation needed

        // Only configure DNS if explicitly requested
        // If not set, containers will use the host's DNS via the VM network
        // Setting DNS causes the framework to write /etc/resolv.conf which can fail on read-only rootfs
        if container.dnsDisabled {
            config.dns = nil
        } else if !container.dnsNameservers.isEmpty || container.dnsDomain != nil || !container.dnsSearchDomains.isEmpty || !container.dnsOptions.isEmpty {
            // User has explicitly configured DNS settings, so apply them
            let domain: String? = container.dnsDomain ?? DefaultsStore.getOptional(key: .defaultDNSDomain)
            
            let dnsConfig = ContainerConfiguration.DNSConfiguration(
                nameservers: container.dnsNameservers.isEmpty ? getHostDNSServers() : container.dnsNameservers,
                domain: domain,
                searchDomains: container.dnsSearchDomains,
                options: container.dnsOptions
            )
            config.dns = dnsConfig
        } else {
            // No DNS configuration specified - let it use host DNS via VM network
            config.dns = nil
        }

        if Platform.current.architecture == "arm64" && platform.architecture == "amd64" {
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
        
        let defaultNetworkName = "default"
        
        // if no networks specified, attach to the default network
        return [AttachmentConfiguration(network: defaultNetworkName, options: AttachmentOptions(hostname: fqdn ?? containerId))]
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
    
    // MARK: - DNS Helpers
    
    /// Read the host's DNS nameservers from /etc/resolv.conf, falling back to public DNS.
    private func getHostDNSServers() -> [String] {
        if let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            let servers = contents.components(separatedBy: .newlines)
                .filter { $0.hasPrefix("nameserver ") }
                .compactMap { $0.split(separator: " ").last.map(String.init) }
                .filter { !$0.isEmpty } // Filter out empty entries
            if !servers.isEmpty {
                return servers
            }
        }
        // Fallback to public DNS if /etc/resolv.conf is unavailable or has no nameservers
        return ["8.8.8.8", "1.1.1.1"]
    }

}
