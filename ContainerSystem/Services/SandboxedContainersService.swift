//
//  SandboxedContainersService.swift
//  Containers
//
//  A containers service that runs LinuxContainer directly in-process,
//  bypassing XPC and child process spawning entirely.
//
//  Created by Axel Martinez on 2026/02/04.
//

import Foundation
import ContainerAPIClient
import ContainerAPIService
import ContainerPlugin
import ContainerSandboxService
import ContainerImagesService
import ContainerNetworkService
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOS
import SystemPackage
import ContainerizationOCI
import ContainerResource
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
public actor SandboxedContainersService {

    private struct ContainerState {
        var snapshot: ContainerSnapshot
        var container: LinuxContainer?
        var bundle: ContainerResource.Bundle?
        var exitMonitorTask: Task<Void, Never>?
    }

    private let log: Logger
    private let appRoot: URL
    private let containerRoot: URL
    private let imagesService: ImagesService
    private var containers: [String: ContainerState] = [:]
    private var ipAllocations: [String: UInt8] = [:]

    init(appRoot: URL, imagesService: ImagesService, log: Logger) throws {
        let containerRoot = appRoot.appendingPathComponent("containers")
        
        try FileManager.default.createDirectory(at: containerRoot, withIntermediateDirectories: true)
        
        self.appRoot = appRoot
        self.containerRoot = containerRoot
        self.imagesService = imagesService
        self.log = log
        self.containers = Self.loadAtBoot(root: containerRoot, log: log)

        let count = containers.count
        
        log.info("SandboxedContainersService initialized with \(count) existing container(s)")
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
                let bundle = ContainerResource.Bundle(path: dir)
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
                log.info("Restored container from disk: \(config.id)")
            } catch {
                log.warning("Failed to load container bundle at \(dir.path): \(error)")
            }
        }
        return results
    }

    // MARK: - Public API

    public func list() async -> [ContainerSnapshot] {
        return containers.values.map { $0.snapshot }
    }

    public func create(configuration: ContainerConfiguration, kernel: Kernel, options: ContainerCreateOptions) async throws {
        log.info("=== Creating container: \(configuration.id) ===")

        guard containers[configuration.id] == nil else {
            throw ContainerizationError(.exists, message: "container already exists: \(configuration.id)")
        }

        let path = containerRoot.appendingPathComponent(configuration.id)
        let systemPlatform = kernel.platform

        // Get init filesystem
        let initFs = try await getInitBlock(for: systemPlatform.ociPlatform())

        // Create container bundle
        let bundle = try ContainerResource.Bundle.create(
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

            log.info("=== Container created successfully: \(configuration.id) ===")

        } catch {
            log.error("Failed to create container: \(error)")
            try? bundle.delete()
            throw error
        }
    }

    public func bootstrap(id: String, stdio: [FileHandle?]) async throws {
        log.info("Bootstrapping container: \(id)")

        guard var state = containers[id] else {
            throw ContainerizationError(.notFound, message: "container with ID \(id) not found")
        }

        // Already bootstrapped
        if state.container != nil {
            log.info("Container already bootstrapped: \(id)")
            return
        }

        let bundle: ContainerResource.Bundle
        if let existingBundle = state.bundle {
            bundle = existingBundle
        } else {
            let path = containerRoot.appendingPathComponent(id)
            bundle = ContainerResource.Bundle(path: path)
        }

        let config = try bundle.configuration
        let bundleKernel = try bundle.kernel
        let initMount = await MainActor.run { bundle.initialFilesystem.asMount }
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

        let stdin: FileHandle? = {
            stdio[0] ?? nil
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
        
        log.info("Container \(id) assigned IP: \(ip)")
        
        let ipWithoutPrefix = String(ip.split(separator: "/").first ?? Substring(ip))
        let dnsServers = Self.getHostDNSServers()

        let container = try LinuxContainer(id, rootfs: rootfs, vmm: vmm, logger: self.log) { czConfig in
            try Self.configureContainer(
                czConfig: &czConfig,
                config: config,
                precomputedMounts: precomputedMounts,
                precomputedSockets: precomputedSockets
            )
            // Configure NATInterface (IsolatedInterfaceStrategy pattern)
            czConfig.interfaces = [try NATInterface(ipv4Address: CIDRv4(ip), ipv4Gateway: IPv4Address(gw))]

            // DNS: use host nameservers if none were explicitly configured.
            // ContainerManager may set czConfig.dns with empty nameservers by default,
            // so we check for both nil and empty.
            if czConfig.dns == nil || (czConfig.dns?.nameservers ?? []).isEmpty {
                czConfig.dns = DNS(nameservers: dnsServers)
            }

            // Hosts: localHostIPV4 + container hostname (matches SandboxService bootstrap)
            czConfig.hosts = Hosts(entries: [
                Hosts.Entry.localHostIPV4(),
                Hosts.Entry(ipAddress: ipWithoutPrefix, hostnames: [czConfig.hostname])
            ])

            czConfig.process.stdout = stdout
            czConfig.process.stderr = stderr
            czConfig.process.stdin = stdin
            // bootlog configuration moved or removed in newer API
        }

        do {
            try await container.create()
            log.info("LinuxContainer VM created and booted for: \(id)")

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

            log.info("Container bootstrapped successfully: \(id)")
        } catch {
            log.error("Failed to bootstrap container \(id): \(error)")
            releaseIP(for: id)
            throw error
        }
    }

    public func startProcess(id: String, processID: String) async throws {
        log.info("Starting process \(processID) in container: \(id)")

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
        log.info("Container init process started: \(id)")

        if isInit {
            state.snapshot.status = .running

            // Monitor container exit in background
            let logger = self.log
            state.exitMonitorTask = Task { [weak self] in
                do {
                    let exitStatus = try await container.wait()
                    logger.info("Container \(id) exited with code: \(exitStatus.exitCode)")
                } catch {
                    logger.error("Error waiting for container \(id): \(error)")
                }
                await self?.handleContainerExit(id: id)
            }

            containers[id] = state
        }

        log.info("Process started: \(processID)")
    }

    public func stop(id: String, options: ContainerStopOptions) async throws {
        log.info("Stopping container: \(id)")

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
        containers[id] = state

        log.info("Container stopped: \(id)")
    }

    public func delete(id: String) async throws {
        log.info("Deleting container: \(id)")

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

        log.info("Container deleted: \(id)")
    }

    /// Execute a command in a running container and return its output (uses vsock, no networking needed).
    public func exec(id: String, arguments: [String]) async throws -> String {
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

        log.info("exec in \(id): \(arguments) → exit \(exitStatus.exitCode)")
        return output
    }

    public func dial(id: String, port: UInt32) async throws -> FileHandle {
        guard let state = containers[id], let container = state.container else {
            throw ContainerizationError(.invalidState, message: "container not running: \(id)")
        }

        log.info("Dialing vsock port \(port) on container: \(id)")
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

    // MARK: - DNS

    /// Read the host's DNS nameservers from /etc/resolv.conf, falling back to public DNS.
    private nonisolated static func getHostDNSServers() -> [String] {
        if let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            let servers = contents.components(separatedBy: .newlines)
                .filter { $0.hasPrefix("nameserver ") }
                .compactMap { $0.split(separator: " ").last.map(String.init) }
            if !servers.isEmpty {
                return servers
            }
        }
        return ["8.8.8.8", "1.1.1.1"]
    }

    // MARK: - Private Methods

    private func handleContainerExit(id: String) {
        guard var state = containers[id] else { return }
        state.snapshot.status = .stopped
        state.snapshot.networks = []
        releaseIP(for: id)
        containers[id] = state
    }

    private func gracefulStopContainer(_ lc: LinuxContainer, stopOpts: ContainerStopOptions) async throws {
        // Try to gracefully shut down the process, then force-stop the VM.
        do {
            _ = try await withThrowingTaskGroup(of: ExitStatus.self) { group in
                group.addTask {
                    try await lc.wait()
                }
                group.addTask {
                    try await lc.kill(stopOpts.signal)
                    try await Task.sleep(for: .seconds(stopOpts.timeoutInSeconds))
                    try await lc.kill(SIGKILL)
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

    private nonisolated static func configureContainer(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration,
        precomputedMounts: [Containerization.Mount],
        precomputedSockets: [UnixSocketConfiguration]
    ) throws {
        czConfig.cpus = config.resources.cpus
        czConfig.memoryInBytes = config.resources.memoryInBytes
        czConfig.sysctl = config.sysctls.reduce(into: [String: String]()) {
            $0[$1.key] = $1.value
        }
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

        if let dns = config.dns {
            czConfig.dns = DNS(
                nameservers: dns.nameservers, domain: dns.domain,
                searchDomains: dns.searchDomains, options: dns.options)
        }

        Self.configureInitialProcess(czConfig: &czConfig, config: config)
    }

    private nonisolated static func configureInitialProcess(
        czConfig: inout LinuxContainer.Configuration,
        config: ContainerConfiguration
    ) {
        let process = config.initProcess

        czConfig.process.arguments = [process.executable] + process.arguments
        czConfig.process.environmentVariables = process.environment

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
}
