//
//  ContainersService.swift
//  Containers
//
//  A containers service that runs LinuxContainer directly in-process,
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOS
import SystemPackage
import ContainerizationOCI
import Logging

private struct MultiWriter: Writer {
    let handles: [FileHandle]

    init(handles: [FileHandle]) {
        self.handles = handles
    }

    func close() throws {
        for handle in handles {
            try handle.close()
        }
    }

    func write(_ data: Data) throws {
        for handle in handles {
            try handle.write(contentsOf: data)
        }
    }
}

private struct FileHandleReader: ReaderStream {
    let handle: FileHandle

    func stream() -> AsyncStream<Data> {
        .init { cont in
            self.handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    cont.finish()
                    return
                }
                cont.yield(data)
            }
        }
    }
}

private extension Filesystem {
    var asMount: Containerization.Mount {
        switch self.type {
        case .tmpfs:
            return .any(
                type: "tmpfs",
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .virtiofs:
            return .share(
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .block(let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        case .volume(_, let format, _, _):
            return .block(
                format: format,
                source: self.source,
                destination: self.destination,
                options: self.options
            )
        }
    }

    func isSocket() throws -> Bool {
        if !self.isVirtiofs {
            return false
        }
        let info = try File.info(self.source)
        
        return info.isSocket
    }
}

/// A sandbox-compatible containers service that runs LinuxContainer in-process.
internal actor ContainersService {

    private struct ContainerState {
        var snapshot: ContainerSnapshot
        var container: LinuxContainer?
        var bundle: Bundle?
        var exitMonitorTask: Task<Void, Never>?
    }

    private let log: Logger
    private let appRoot: URL
    private let containerRoot: URL
    private let imagesService: ImagesService
    private var containers: [String: ContainerState] = [:]
    private var ipAllocations: [String: UInt8] = [:]
    private var portForwarders: [String: PortForwarder] = [:]
    private let containerLock = AsyncLock()
    
    /// Callbacks to invoke when container state changes
    private var stateChangeCallbacks: [@Sendable @MainActor () -> Void] = []
    
    /// Register a callback to be invoked when container state changes
    internal func addStateChangeCallback(_ callback: @escaping @Sendable @MainActor () -> Void) {
        stateChangeCallbacks.append(callback)
    }

    internal init(appRoot: URL, imagesService: ImagesService, log: Logger) throws {
        let containerRoot = appRoot.appendingPathComponent("containers")
        
        try FileManager.default.createDirectory(at: containerRoot, withIntermediateDirectories: true)
        
        self.appRoot = appRoot
        self.containerRoot = containerRoot
        self.imagesService = imagesService
        self.log = log
        self.containers = Self.loadAtBoot(root: containerRoot, log: log)

        let count = containers.count
        
        log.info("ContainersService initialized with \(count) existing container(s)")
    }

    private static func loadAtBoot(root: URL, log: Logger) -> [String: ContainerState] {
        var results = [String: ContainerState]()
        
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return results
        }

        for dir in directories where dir.isDirectory {
            do {
                let bundle = Bundle(path: dir)
                let config = try bundle.configuration
                results[config.id] = ContainerState(
                    snapshot: ContainerSnapshot(
                        configuration: config,
                        status: .stopped,
                        networks: []
                    ),
                    container: LinuxContainer?.none,
                    bundle: bundle
                )
                // Container restored from disk
            } catch {
                log.warning("Failed to load container bundle at \(dir.path): \(error)")
            }
        }
        return results
    }

    // MARK: - Internal API

    internal func list() async -> [ContainerSnapshot] {
        return containers.values.map { $0.snapshot }.sorted { $0.configuration.id < $1.configuration.id }
    }
    
    /// List containers with optional filters.
    internal func list(
        status: RuntimeStatus? = nil,
        labelFilter: [String: String]? = nil,
        namePattern: String? = nil
    ) async -> [ContainerSnapshot] {
        var results = containers.values.map { $0.snapshot }
        
        if let status {
            results = results.filter { $0.status == status }
        }
        
        if let labelFilter {
            results = results.filter { snapshot in
                labelFilter.allSatisfy { key, value in
                    snapshot.configuration.labels[key] == value
                }
            }
        }
        
        if let namePattern, !namePattern.isEmpty {
            results = results.filter { snapshot in
                snapshot.id.localizedCaseInsensitiveContains(namePattern)
            }
        }
        
        return results.sorted { $0.configuration.id < $1.configuration.id }
    }

    internal func create(configuration: ContainerConfiguration, kernel: Kernel, options: ContainerCreateOptions) async throws {
        // Creating container

        guard containers[configuration.id] == nil else {
            throw ContainerizationError(.exists, message: "container already exists: \(configuration.id)")
        }

        let path = containerRoot.appendingPathComponent(configuration.id)
        let systemPlatform = kernel.platform

        // Get init filesystem
        let initFs = try await getInitBlock(for: systemPlatform.ociPlatform())

        // Create container bundle
        let bundle = try Bundle.create(
            path: path,
            initialFilesystem: initFs,
            kernel: kernel,
            containerConfiguration: configuration
        )

        do {
            // Get container image filesystem via in-process ImagesService (no XPC)
            let imageFs = try await imagesService.getImageSnapshot(description: configuration.image, platform: configuration.platform)
            try bundle.setContainerRootFs(cloning: imageFs)
            try bundle.write(filename: "options.json", value: options)

            let snapshot = ContainerSnapshot(
                configuration: configuration,
                status: .stopped,
                networks: []
            )
            containers[configuration.id] = ContainerState(
                snapshot: snapshot,
                container: LinuxContainer?.none,
                bundle: bundle
            )

            // Container created successfully

        } catch {
            log.error("Failed to create container: \(error)")
            try? bundle.delete()
            throw error
        }
    }

    internal func bootstrap(id: String, stdio: [FileHandle?]) async throws {
        try await containerLock.withLock { _ in
            try await self._bootstrap(id: id, stdio: stdio)
        }
    }

    private func _bootstrap(id: String, stdio: [FileHandle?]) async throws {
        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        // Already bootstrapped
        if state.container != nil {
            return
        }

        let bundle: ContainerSystem.Bundle
        if let existingBundle = state.bundle {
            bundle = existingBundle
        } else {
            let path = containerRoot.appendingPathComponent(id)
            bundle = Bundle(path: path)
        }

        let config = try bundle.configuration
        let bundleKernel = try bundle.kernel
        let initMount = try await MainActor.run { try bundle.initialFilesystem.asMount }
        let vmm = VZVirtualMachineManager(
            kernel: bundleKernel,
            initialFilesystem: initMount,
            rosetta: config.rosetta,
            logger: self.log
        )

        // Create the log file for container stdio
        let containerLogURL = bundle.path.appendingPathComponent("stdio.log")
        
        do {
            let fd = Darwin.open(containerLogURL.path, O_CREAT | O_RDONLY | O_TRUNC, 0o644)
            guard fd >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
            Darwin.close(fd)
        }

        // Set up stdio writers
        let containerLog = try FileHandle(forWritingTo: containerLogURL)
        let stdout: MultiWriter = {
            if let h = stdio[1] {
                return MultiWriter(handles: [h, containerLog])
            }
            return MultiWriter(handles: [containerLog])
        }()

        let stderr: MultiWriter? = {
            if !config.initProcess.terminal {
                if let h = stdio[2] {
                    return MultiWriter(handles: [h, containerLog])
                }
                return MultiWriter(handles: [containerLog])
            }
            return nil
        }()

        let stdin: FileHandleReader? = {
            if let handle = stdio[0] {
                return FileHandleReader(handle: handle)
            }
            return nil
        }()

        let rootfs = try await MainActor.run { try bundle.containerRootfs.asMount }

        // Precompute mounts and sockets
        var precomputedMounts: [Containerization.Mount] = []
        var precomputedSockets: [UnixSocketConfiguration] = []
        
        for mount in config.mounts {
            if try await MainActor.run(body: { try mount.isSocket() }) {
                let socket = UnixSocketConfiguration(
                    source: URL(filePath: mount.source),
                    destination: URL(filePath: mount.destination)
                )
                precomputedSockets.append(socket)
            } else {
                let mnt = await MainActor.run { mount.asMount }
                precomputedMounts.append(mnt)
            }
        }

        // Allocate IP before the closure (actor-isolated state)
        let (ip, gw) = try allocateIP(for: id)
        
        let container = try LinuxContainer(id, rootfs: rootfs, vmm: vmm, logger: self.log) { czConfig in
            try Self.configureContainer(
                czConfig: &czConfig,
                config: config,
                precomputedMounts: precomputedMounts,
                precomputedSockets: precomputedSockets
            )
            // Configure NATInterface (IsolatedInterfaceStrategy pattern)
            czConfig.interfaces = [try NATInterface(ipv4Address: CIDRv4(ip), ipv4Gateway: IPv4Address(gw))]

            // Do not set hosts configuration - causes I/O errors when framework tries to write /etc/hosts
            // The framework will handle hosts automatically

            czConfig.process.stdout = stdout
            czConfig.process.stderr = stderr
            czConfig.process.stdin = stdin
        }

        do {
            try await container.create()

            state.container = container
            state.bundle = bundle
            state.snapshot.networks = [
                Attachment(
                    network: "nat",
                    hostname: id,
                    ipv4Address: try CIDRv4(ip),
                    ipv4Gateway: try IPv4Address(gw),
                    ipv6Address: CIDRv6?.none,
                    macAddress: MACAddress?.none
                )
            ]
            containers[id] = state
            
            // Notify observers that networks have been assigned
            notifyStateChange()
        } catch {
            log.error("Failed to bootstrap container \(id): \(error)")
            releaseIP(for: id)
            throw error
        }
    }

    internal func startProcess(id: String, processID: String) async throws {
        // Starting process in container

        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        let isInit = id == processID
        if state.snapshot.status == .running && isInit {
            return
        }

        guard let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not bootstrapped: \(id)")
        }

        try await container.start()
        // Container init process started

        if isInit {
            state.snapshot.status = .running
            state.snapshot.startedDate = Date()

            // Start port forwarding for published ports
            let config = state.snapshot.configuration
            if !config.publishedPorts.isEmpty {
                let forwarder = PortForwarder(log: self.log)
                for port in config.publishedPorts {
                    do {
                        try await forwarder.startForwarding(publishPort: port, container: container)
                    } catch {
                        log.warning("Failed to start port forwarding for \(port.hostPort) -> \(port.containerPort): \(error)")
                    }
                }
                portForwarders[id] = forwarder
            }

            // Monitor container exit in background
            let logger = self.log
            
            state.exitMonitorTask = Task { [weak self] in
                do {
                    try await container.wait()
                    // Container exited
                } catch {
                    logger.error("Error waiting for container \(id): \(error)")
                }
                await self?.handleContainerExit(id: id)
            }

            containers[id] = state
            
            // Notify observers that container started
            notifyStateChange()
        }
    }

    internal func stop(id: String, options: ContainerStopOptions) async throws {
        try await containerLock.withLock { _ in
            try await self._stop(id: id, options: options)
        }
    }

    private func _stop(id: String, options: ContainerStopOptions) async throws {
        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        if let container = state.container {
            do {
                try await gracefulStopContainer(container, stopOpts: options)
            } catch let err as ContainerizationError {
                if err.code != .interrupted {
                    throw err
                }
            } catch {
                log.error("Error during graceful stop of container \(id): \(error)")
            }
        }

        state.exitMonitorTask?.cancel()
        state.exitMonitorTask = nil
        state.snapshot.status = .stopped
        state.snapshot.networks = []
        state.container = nil
        releaseIP(for: id)
        
        // Stop port forwarding
        if let forwarder = portForwarders.removeValue(forKey: id) {
            await forwarder.stopAll()
        }
        
        containers[id] = state
        
        // Notify observers that container stopped
        notifyStateChange()
    }

    internal func delete(id: String) async throws {
        guard let state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        if state.snapshot.status == .running {
            throw ContainerizationError(.invalidState, message: "cannot delete running container")
        }

        // Delete container bundle
        let path = containerRoot.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: path)

        releaseIP(for: id)
        containers.removeValue(forKey: id)
        notifyStateChange()
    }
    
    internal func updateMounts(id: String, mounts: [Filesystem]) async throws {
        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }
        
        guard state.snapshot.status == .stopped else {
            throw ContainerizationError(.invalidState, message: "container must be stopped before changing volume mounts")
        }
        
        let bundle = state.bundle ?? Bundle(path: containerRoot.appendingPathComponent(id))
        var configuration = state.snapshot.configuration
        configuration.mounts = mounts
        
        try bundle.setConfiguration(configuration)
        state.snapshot.configuration = configuration
        state.bundle = bundle
        containers[id] = state
        notifyStateChange()
    }

    /// Execute a command in a running container and return its output (uses vsock, no networking needed).
    internal func exec(id: String, arguments: [String]) async throws -> String {
        guard let state = containers[id], let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        let outputURL = containerRoot.appendingPathComponent("\(id)-exec-output.tmp")
        
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let writer = MultiWriter(handles: [outputHandle])

        let process = try await container.exec("exec-\(UUID().uuidString)") { config in
            config.arguments = arguments
            config.stdout = writer
            config.stderr = writer
        }

        try await process.start()
        
        let exitStatus = try await process.wait()
        
        try? writer.close()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        
        try? FileManager.default.removeItem(at: outputURL)
        
        if exitStatus.exitCode != 0 {
            throw ContainerizationError(.internalError, message: "command failed with exit code \(exitStatus.exitCode): \(output)")
        }
        
        return output
    }

    internal func dial(id: String, port: UInt32) async throws -> FileHandle {
        guard let state = containers[id], let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        // Dialing vsock port
        return try await container.dialVsock(port: port)
    }

    // MARK: - IP Allocation

    private func allocateIP(for id: String) throws -> (address: String, gateway: String) {
        if let existing = ipAllocations[id] {
            return (address: "192.168.64.\(existing)/24", gateway: "192.168.64.1")
        }
        for i: UInt8 in 2...254 {
            if !ipAllocations.values.contains(i) {
                ipAllocations[id] = i
                return (address: "192.168.64.\(i)/24", gateway: "192.168.64.1")
            }
        }
        throw ContainerizationError(
            .internalError,
            message: "no available IP addresses"
        )
    }

    private func releaseIP(for id: String) {
        ipAllocations.removeValue(forKey: id)
    }

    // MARK: - Private Methods

    private func handleContainerExit(id: String) {
        guard var state = containers[id] else {
            log.warning("Container \(id) not found during exit handling")
            return
        }
        state.snapshot.status = .stopped
        state.snapshot.networks = []
        state.container = nil
        state.exitMonitorTask?.cancel()
        state.exitMonitorTask = nil
        releaseIP(for: id)
        
        // Stop port forwarding
        if let forwarder = portForwarders.removeValue(forKey: id) {
            Task { await forwarder.stopAll() }
        }
        
        containers[id] = state
        
        notifyStateChange()
    }

    private func gracefulStopContainer(_ lc: LinuxContainer, stopOpts: ContainerStopOptions) async throws {
        // Try to gracefully shut down the process, then force-stop the VM.
        do {
            _ = try await withThrowingTaskGroup(of: ExitStatus.self) { group in
                group.addTask {
                    try await lc.wait()
                }
                group.addTask {
                    try await lc.kill(Signal(rawValue: stopOpts.signal))
                    try await Task.sleep(for: .seconds(stopOpts.timeoutInSeconds))
                    try await lc.kill(Signal(rawValue: SIGKILL))
                    return ExitStatus(exitCode: 137)
                }
                guard let code = try await group.next() else {
                    throw ContainerizationError(
                        .internalError,
                        message: "failed to get exit code from gracefully stopping container"
                    )
                }
                group.cancelAll()
                return code
            }
        } catch {
            log.notice("graceful stop failed, forcing: \(error)")
        }

        // Bring down the VM
        try await lc.stop()
    }

    private static func configureContainer(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration,
        precomputedMounts: [Containerization.Mount],
        precomputedSockets: [UnixSocketConfiguration]
    ) throws {
        czConfig.cpus = config.resources.cpus
        czConfig.memoryInBytes = config.resources.memoryInBytes
        czConfig.sysctl = config.sysctls
        czConfig.virtualization = config.virtualization

        // Use precomputed mounts and sockets
        czConfig.mounts.append(contentsOf: precomputedMounts)
        czConfig.sockets.append(contentsOf: precomputedSockets)

        for publishedSocket in config.publishedSockets {
            let socketConfig = UnixSocketConfiguration(
                source: publishedSocket.containerPath,
                destination: publishedSocket.hostPath,
                permissions: publishedSocket.permissions,
                direction: .outOf
            )
            czConfig.sockets.append(socketConfig)
        }

        if config.ssh, let sshSocket = Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            let socketUrl = URL(fileURLWithPath: sshSocket)
            let socketPath = socketUrl.path(percentEncoded: false)
            let attrs = try? FileManager.default.attributesOfItem(atPath: socketPath)
            let permissions = (attrs?[.posixPermissions] as? NSNumber)
                .map { FilePermissions(rawValue: mode_t($0.intValue)) }
            let socketConfig = UnixSocketConfiguration(
                source: socketUrl,
                destination: URL(fileURLWithPath: "/run/host-services/ssh-auth.sock"),
                permissions: permissions,
                direction: .into
            )
            czConfig.sockets.append(socketConfig)
        }

        czConfig.hostname = config.id

        // Only set DNS if explicitly provided by container configuration
        // Setting DNS causes the framework to write /etc/resolv.conf which fails on read-only rootfs
        // If not set, containers will use the host's DNS via the VM network
        if let dns = config.dns, !dns.nameservers.isEmpty {
            czConfig.dns = DNS(
                nameservers: dns.nameservers, domain: dns.domain,
                searchDomains: dns.searchDomains, options: dns.options)
        }

        try Self.configureInitialProcess(czConfig: &czConfig, config: config)
    }

    private static func configureInitialProcess(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration
    ) throws {
        let process = config.initProcess

        czConfig.process.arguments = [process.executable] + process.arguments
        czConfig.process.environmentVariables = process.environment
        czConfig.process.capabilities = try capabilities(from: config.capabilities)

        if config.ssh, Foundation.ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] != nil {
            let sshEnvVar = "SSH_AUTH_SOCK"
            let sshGuestPath = "/run/host-services/ssh-auth.sock"
            if !czConfig.process.environmentVariables.contains(where: { $0.starts(with: "\(sshEnvVar)=") }) {
                czConfig.process.environmentVariables.append("\(sshEnvVar)=\(sshGuestPath)")
            }
        }

        czConfig.process.terminal = process.terminal
        czConfig.process.workingDirectory = process.workingDirectory
        czConfig.process.rlimits = process.rlimits.compactMap {
            guard let kind = try? LinuxRLimit.Kind($0.limit) else { return nil }
            return .init(kind: kind, hard: $0.hard, soft: $0.soft)
        }
        switch process.user {
        case .raw(let name):
            czConfig.process.user = .init(
                uid: 0,
                gid: 0,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: name
            )
        case .id(let uid, let gid):
            czConfig.process.user = .init(
                uid: uid,
                gid: gid,
                umask: nil,
                additionalGids: process.supplementalGroups,
                username: ""
            )
        }
    }
    
    private static func capabilities(from names: [String]) throws -> Containerization.LinuxCapabilities {
        let capabilities = try capabilitySet(from: names)
        
        guard !capabilities.isEmpty else {
            return .allCapabilities
        }
        
        return Containerization.LinuxCapabilities(capabilities: Array(capabilities))
    }
    
    private static func capabilitySet(from names: [String]) throws -> Set<CapabilityName> {
        var capabilities: Set<CapabilityName> = []
        
        for name in names {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedName.isEmpty else {
                continue
            }
            
            if trimmedName.uppercased() == "ALL" {
                capabilities.formUnion(CapabilityName.allCases)
            } else {
                capabilities.insert(try CapabilityName(rawValue: trimmedName))
            }
        }
        
        return capabilities
    }

    private func getInitBlock(for platform: Platform) async throws -> Filesystem {
        // Use in-process ImagesService to get the init image snapshot (no XPC)
        let initImageRef = ClientImage.initImageRef
        let initDescription = try await imagesService.pull(
            reference: initImageRef,
            platform: platform,
            insecure: false,
            progressUpdate: nil
        )
        try await imagesService.unpack(
            description: initDescription,
            platform: platform,
            progressUpdate: nil
        )
        var fs = try await imagesService.getImageSnapshot(description: initDescription, platform: platform)
        fs.options = ["ro"]
        return fs
    }
    
    /// Notify all registered callbacks that container state changed
    private func notifyStateChange() {
        for callback in stateChangeCallbacks {
            Task { @MainActor in
                callback()
            }
        }
    }
}
