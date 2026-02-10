//
//  SandboxedBuilder.swift
//  Containers
//
//  Sandboxed version of Builder that implements build protocol without XPC dependencies
//
//  Created by Axel Martinez on 2026/02/09.
//

import Foundation
import ContainerBuild
import ContainerImagesService
import ContainerResource
import Containerization
import ContainerizationOCI
import ContainerizationError
import ContainerizationOS
import GRPC
import NIO
import Logging

/// Standalone sandboxed builder that uses ImagesService instead of XPC-based ClientImage
public struct SandboxedBuilder: Sendable {
    public static let builderContainerId = "buildkit"
    
    let client: BuilderClientProtocol
    let clientAsync: BuilderClientAsyncProtocol
    let group: EventLoopGroup
    let builderShimSocket: FileHandle
    let channel: GRPCChannel
    let imagesService: ImagesService
    let contentStore: ContentStore
    private let logger: Logger
    
    public init(socket: FileHandle, group: EventLoopGroup, imagesService: ImagesService, contentStore: ContentStore) throws {
        // Socket buffer configuration would be done here if the APIs were public
        // For now we skip this as setSendBufSize/setRecvBufSize are internal
        var config = ClientConnection.Configuration.default(
            target: .connectedSocket(socket.fileDescriptor),
            eventLoopGroup: group
        )
        config.connectionIdleTimeout = TimeAmount(.seconds(600))
        config.connectionKeepalive = .init(
            interval: TimeAmount(.seconds(600)),
            timeout: TimeAmount(.seconds(500)),
            permitWithoutCalls: true
        )
        config.connectionBackoff = .init(
            initialBackoff: TimeInterval(1),
            maximumBackoff: TimeInterval(10)
        )
        config.callStartBehavior = .fastFailure
        config.httpMaxFrameSize = 8 << 10
        config.maximumReceiveMessageLength = 512 << 20
        config.httpTargetWindowSize = 16 << 10

        let channel = ClientConnection(configuration: config)
        self.channel = channel
        self.clientAsync = BuilderClientAsync(channel: channel)
        self.client = BuilderClient(channel: channel)
        self.group = group
        self.builderShimSocket = socket
        self.imagesService = imagesService
        self.contentStore = contentStore
        
        var logger = Logger(label: "app.containers.sandboxed-builder")
        logger.logLevel = .info
        self.logger = logger
    }
    
    public func info() async throws -> InfoResponse {
        let opts = CallOptions(timeLimit: .timeout(.seconds(30)))
        return try await self.clientAsync.info(InfoRequest(), callOptions: opts)
    }
    
    /// Perform a sandboxed build using custom pipeline that handles image resolution
    public func build(_ config: Builder.BuildConfig) async throws {
        let logger = Logger(label: "app.containers.sandboxed-builder.build")
        logger.info("SandboxedBuilder.build() called with buildID: \(config.buildID)")
        
        var continuation: AsyncStream<ClientStream>.Continuation?
        let reqStream = AsyncStream<ClientStream> { (cont: AsyncStream<ClientStream>.Continuation) in
            continuation = cont
        }
        guard let continuation else {
            throw SandboxedBuilderError.invalidContinuation
        }

        defer {
            continuation.finish()
        }

        // Terminal handling would go here if needed
        // For now, we skip this as it requires internal TerminalCommand type

        logger.info("Creating gRPC stream to BuildKit")
        logger.info("Build config: buildID=\(config.buildID), contextDir=\(config.contextDir)")
        logger.info("Build config: dockerfile size=\(config.dockerfile.count) bytes, tags=\(config.tags)")
        logger.info("Build config: platforms=\(config.platforms.map { $0.description }), target=\(config.target)")
        logger.info("Build config: exports=\(config.exports.map { $0.type })")
        
        let respStream = self.clientAsync.performBuild(reqStream, callOptions: try CallOptions(config))
        
        logger.info("Initializing sandboxed build pipeline")
        let pipeline = SandboxedBuildPipeline(
            config: config,
            imagesService: self.imagesService,
            contentStore: self.contentStore
        )
        
        logger.info("Starting pipeline execution")
        
        // Start a background task to log progress
        let progressTask = Task {
            try? await Task.sleep(for: .seconds(30))
            logger.warning("Pipeline has been running for 30 seconds without completion")
            try? await Task.sleep(for: .seconds(30))
            logger.error("Pipeline has been running for 60 seconds - BuildKit may not be responding")
        }
        
        do {
            try await pipeline.run(sender: continuation, receiver: respStream)
            progressTask.cancel()
            logger.info("Build completed successfully")
        } catch {
            progressTask.cancel()
            
            // Check if this is the normal build complete signal
            if let builderError = error as? SandboxedBuilderError, builderError == .buildComplete {
                logger.info("Build completed successfully")
                return
            }
            
            logger.error("Pipeline execution failed: \(error)")
            _ = channel.close()
            try await group.shutdownGracefully()
            throw error
        }
    }
}

// MARK: - Sandboxed Build Pipeline

/// Custom build pipeline that uses ImagesService for image resolution instead of XPC
private actor SandboxedBuildPipeline {
    let config: Builder.BuildConfig
    let imagesService: ImagesService
    let contentStore: ContentStore
    let logger: Logger
    
    init(config: Builder.BuildConfig, imagesService: ImagesService, contentStore: ContentStore) {
        self.config = config
        self.imagesService = imagesService
        self.contentStore = contentStore
        var logger = Logger(label: "app.containers.sandboxed-pipeline")
        logger.logLevel = .info
        self.logger = logger
    }
    
    func run(
        sender: AsyncStream<ClientStream>.Continuation,
        receiver: GRPCAsyncResponseStream<ServerStream>
    ) async throws {
        defer { sender.finish() }
        
        logger.info("Build pipeline started")
        var packetCount = 0
        
        for try await packet in receiver {
            try Task.checkCancellation()
            packetCount += 1
            
            if packetCount == 1 {
                logger.info("Received first packet from BuildKit")
            }
            
            // Log packet type
            switch packet.packetType {
            case .imageTransfer(let transfer):
                logger.debug("Packet #\(packetCount): ImageTransfer(stage:\(transfer.stage() ?? "nil"), method:\(transfer.method() ?? "nil"))")
            case .buildTransfer(let transfer):
                logger.debug("Packet #\(packetCount): BuildTransfer(stage:\(transfer.metadata["stage"] ?? "nil"), method:\(transfer.metadata["method"] ?? "nil"))")
            case .io(let io):
                if let message = String(data: io.data, encoding: .utf8), !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    logger.info("\(message)")
                }
            case .buildError(let error):
                logger.error("Build error: \(error.message)")
            case .commandComplete:
                logger.info("Build command completed")
                throw SandboxedBuilderError.buildComplete
            case .none:
                logger.debug("Packet #\(packetCount): Empty")
            }
            
            // Handle different packet types
            if let imageTransfer = packet.getImageTransfer() {
                try await handleImageTransfer(imageTransfer, sender: sender, buildID: packet.buildID)
            } else if let buildTransfer = packet.getBuildTransfer() {
                try await handleBuildTransfer(buildTransfer, sender: sender, buildID: packet.buildID)
            } else if let io = packet.getIO() {
                try await handleIO(io, sender: sender, buildID: packet.buildID)
            }
        }
        
        logger.info("Build pipeline finished (\(packetCount) packets)")
        logger.info("Stream ended - build should be complete")
    }
    
    private func handleImageTransfer(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let stage = imageTransfer.metadata["stage"]
        let method = imageTransfer.metadata["method"]
        
        // Handle resolver requests
        if stage == "resolver" && method == "/resolve" {
            try await handleResolverRequest(imageTransfer, sender: sender, buildID: buildID)
            return
        }
        
        // Handle content-store requests
        if stage == "content-store" {
            try await handleContentStoreRequest(imageTransfer, sender: sender, buildID: buildID)
            return
        }
        
        logger.debug("Skipping ImageTransfer(stage=\(stage ?? "nil"), method=\(method ?? "nil"))")
    }
    
    private func handleResolverRequest(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        guard let ref = imageTransfer.ref() else {
            throw SandboxedBuilderError.imageMissing
        }
        
        guard let platform = try imageTransfer.platform() else {
            throw SandboxedBuilderError.platformMissing
        }
        
        logger.info("Resolving image: \(ref) for platform: \(platform.description)")
        
        let imageDescription = try await pullImage(reference: ref, platform: platform)
        
        guard let indexContent: Content = try await contentStore.get(digest: imageDescription.digest) else {
            throw SandboxedBuilderError.imageNotFound
        }
        let index: Index = try indexContent.decode()
        
        for manifest in index.manifests {
            if manifest.platform == platform {
                guard let manifestContent: Content = try await contentStore.get(digest: manifest.digest) else {
                    continue
                }
                let manifestData: Manifest = try manifestContent.decode()
                
                guard let ociImage: ContainerizationOCI.Image = try await contentStore.get(digest: manifestData.config.digest) else {
                    continue
                }
                
                let enc = JSONEncoder()
                let data = try enc.encode(ociImage)
                let transfer = try ImageTransfer(
                    id: imageTransfer.id,
                    digest: imageDescription.digest,
                    ref: ref,
                    platform: platform.description,
                    data: data
                )
                
                var response = ClientStream()
                response.buildID = buildID
                response.imageTransfer = transfer
                response.packetType = .imageTransfer(transfer)
                sender.yield(response)
                
                logger.info("Resolved: \(ref)")
                return
            }
        }
        
        throw SandboxedBuilderError.unknownPlatformForImage(platform.description, ref)
    }
    
    private func handleContentStoreRequest(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let method = imageTransfer.metadata["method"]
        
        switch method {
        case "/containerd.services.content.v1.Content/Info":
            try await handleContentStoreInfo(imageTransfer, sender: sender, buildID: buildID)
        case "/containerd.services.content.v1.Content/ReaderAt":
            try await handleContentStoreReaderAt(imageTransfer, sender: sender, buildID: buildID)
        default:
            logger.error("Unknown content-store method: \(method ?? "nil")")
        }
    }
    
    private func handleContentStoreInfo(
        _ packet: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is asking for information about a blob in the content store
        let digest = packet.tag
        
        // Get the blob descriptor from content store
        let descriptor = try await contentStore.get(digest: digest)
        let size = try descriptor?.size()
        
        var transfer = ImageTransfer()
        transfer.id = packet.id
        transfer.tag = digest
        transfer.metadata = [
            "os": "linux",
            "stage": "content-store",
            "method": "/containerd.services.content.v1.Content/Info",
        ]
        if let size = size {
            transfer.metadata["size"] = String(size)
        }
        transfer.complete = true
        transfer.direction = .into
        
        var response = ClientStream()
        response.buildID = buildID
        response.imageTransfer = transfer
        response.packetType = .imageTransfer(transfer)
        sender.yield(response)
    }
    
    private func handleContentStoreReaderAt(
        _ packet: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is asking to read data from a blob
        let digest = packet.descriptor.digest
        let offset = UInt64(packet.metadata["offset"] ?? "0") ?? 0
        let length = Int(packet.metadata["length"] ?? "0") ?? 0
        
        guard let descriptor = try await contentStore.get(digest: digest) else {
            logger.error("Blob not found in content store: \(digest)")
            throw SandboxedBuilderError.imageNotInContentStore(digest)
        }
        
        // If offset and length are both 0, this is a metadata request (just size)
        if offset == 0 && length == 0 {
            let size = try descriptor.size()
            var transfer = ImageTransfer()
            transfer.id = packet.id
            transfer.tag = digest
            transfer.metadata = [
                "os": "linux",
                "stage": "content-store",
                "method": "/containerd.services.content.v1.Content/ReaderAt",
                "size": String(size),
            ]
            transfer.complete = true
            transfer.direction = .into
            transfer.data = Data()
            
            var response = ClientStream()
            response.buildID = buildID
            response.imageTransfer = transfer
            response.packetType = .imageTransfer(transfer)
            sender.yield(response)
            return
        }
        
        // Read the blob data at the requested offset and length
        guard let data = try descriptor.data(offset: offset, length: length) else {
            logger.error("Failed to read data from content store: digest=\(digest), offset=\(offset), length=\(length)")
            throw SandboxedBuilderError.imageNotInContentStore(digest)
        }
        
        var transfer = ImageTransfer()
        transfer.id = packet.id
        transfer.tag = digest
        transfer.metadata = [
            "os": "linux",
            "stage": "content-store",
            "method": "/containerd.services.content.v1.Content/ReaderAt",
        ]
        transfer.complete = true
        transfer.direction = .into
        transfer.data = data
        
        var response = ClientStream()
        response.buildID = buildID
        response.imageTransfer = transfer
        response.packetType = .imageTransfer(transfer)
        sender.yield(response)
    }
    
    private func handleBuildTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildTransfer packets are used for syncing files (both build context and exports)
        let stage = buildTransfer.metadata["stage"]
        let direction = buildTransfer.direction
        
        logger.info("BuildTransfer: stage=\(stage ?? "nil"), direction=\(direction), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)")
        
        switch stage {
        case "fssync":
            // Handle build context file sync
            try await handleFSSyncTransfer(buildTransfer, sender: sender, buildID: buildID)
        case "export", nil:
            // Handle export file write - BuildKit is trying to write the export tar
            logger.info("Handling export transfer")
            try await handleExportTransfer(buildTransfer, sender: sender, buildID: buildID)
        default:
            logger.warning("Ignoring BuildTransfer with unknown stage: \(stage ?? "unknown")")
        }
    }
    
    private func handleFSSyncTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        guard let method = buildTransfer.metadata["method"] else {
            logger.error("BuildTransfer missing method")
            return
        }
        
        let contextDir = URL(fileURLWithPath: config.contextDir)
        
        switch method {
        case "Read":
            try await handleFSSyncRead(buildTransfer, contextDir: contextDir, sender: sender, buildID: buildID)
        case "Info":
            try await handleFSSyncInfo(buildTransfer, contextDir: contextDir, sender: sender, buildID: buildID)
        case "Walk":
            try await handleFSSyncWalk(buildTransfer, contextDir: contextDir, sender: sender, buildID: buildID)
        default:
            logger.error("Unknown FSSync method: \(method)")
        }
    }
    
    private func handleExportTransfer(
        _ buildTransfer: BuildTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is trying to write export data through the filesync protocol
        // We need to receive the data and write it to the export directory
        
        logger.info("Export transfer: direction=\(buildTransfer.direction), complete=\(buildTransfer.complete), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)")
        
        // The source path from BuildKit is like "/var/lib/container-builder-shim/exports/{buildID}/out.tar"
        // We need to extract the relative path and write to our export directory
        let exportBasePath = "/var/lib/container-builder-shim/exports/"
        guard buildTransfer.source.hasPrefix(exportBasePath) else {
            logger.error("Unexpected export source path: \(buildTransfer.source)")
            return
        }
        
        let relativePath = String(buildTransfer.source.dropFirst(exportBasePath.count))
        
        // Construct the host filesystem path
        // The export directory structure is: appRoot/.build/{buildID}/
        guard let appRoot = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("com.axelmartinez.Containers") else {
            logger.error("Could not determine app root")
            return
        }
        
        let exportPath = appRoot.appendingPathComponent(".build").appendingPathComponent(relativePath)
        
        logger.info("Writing export data to: \(exportPath.path)")
        
        // Create parent directory if needed
        let parentDir = exportPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Write or append the data
        if buildTransfer.data.count > 0 {
            if FileManager.default.fileExists(atPath: exportPath.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: exportPath)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: buildTransfer.data)
            } else {
                // Create new file
                try buildTransfer.data.write(to: exportPath)
            }
        }
        
        // Send acknowledgment back to BuildKit
        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = buildTransfer.id
        response.buildTransfer.source = buildTransfer.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.metadata = [
            "os": "linux"
        ]
        
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
        
        if buildTransfer.complete {
            logger.info("Export transfer complete for: \(exportPath.path)")
        }
    }
    
    private func handleFSSyncRead(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let path = contextDir.appendingPathComponent(packet.source).standardizedFileURL
        
        // Read file data
        let data: Data
        if FileManager.default.fileExists(atPath: path.path) {
            let offset = UInt64(packet.metadata["offset"] ?? "0") ?? 0
            let length = Int(packet.metadata["length"] ?? "0") ?? 0
            
            if path.hasDirectoryPath == true {
                data = Data()
            } else {
                let fileData = try Data(contentsOf: path)
                if offset == 0 && length == 0 {
                    data = fileData
                } else {
                    let start = Int(offset)
                    let end = length > 0 ? start + length : fileData.count
                    data = fileData.subdata(in: start..<min(end, fileData.count))
                }
            }
        } else {
            data = Data()
        }
        
        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = packet.id
        response.buildTransfer.source = packet.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.metadata = [
            "os": "linux",
            "stage": "fssync",
        ]
        response.buildTransfer.data = data
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }
    
    private func handleFSSyncInfo(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let path = contextDir.appendingPathComponent(packet.source).standardizedFileURL
        
        var response = ClientStream()
        response.buildID = buildID
        response.buildTransfer = BuildTransfer()
        response.buildTransfer.id = packet.id
        response.buildTransfer.source = packet.source
        response.buildTransfer.complete = true
        response.buildTransfer.direction = .outof
        response.buildTransfer.isDirectory = path.hasDirectoryPath
        response.buildTransfer.metadata = [
            "os": "linux",
            "stage": "fssync",
        ]
        
        // Add file metadata if file exists
        if FileManager.default.fileExists(atPath: path.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) {
            if let size = attrs[.size] as? UInt64 {
                response.buildTransfer.metadata["size"] = String(size)
            }
            if let mode = attrs[.posixPermissions] as? NSNumber {
                response.buildTransfer.metadata["mode"] = String(mode.uint32Value)
            }
            if let modDate = attrs[.modificationDate] as? Date {
                let formatter = ISO8601DateFormatter()
                response.buildTransfer.metadata["modified_at"] = formatter.string(from: modDate)
            }
            response.buildTransfer.metadata["uid"] = "0"
            response.buildTransfer.metadata["gid"] = "0"
        }
        
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }
    
    private func handleFSSyncWalk(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // BuildKit is asking for a list of files to transfer
        // For now, send back an empty walk response to indicate we have no files
        // A full implementation would enumerate the context directory and send file info
        
        let mode = packet.metadata["mode"] ?? "json"
        
        if mode == "json" {
            // Send JSON list of files
            let fileList: [[String: Any]] = [] // Empty for now
            let jsonData = try JSONSerialization.data(withJSONObject: fileList)
            
            var response = ClientStream()
            response.buildID = buildID
            response.buildTransfer = BuildTransfer()
            response.buildTransfer.id = packet.id
            response.buildTransfer.source = packet.source
            response.buildTransfer.complete = true
            response.buildTransfer.direction = .outof
            response.buildTransfer.isDirectory = false
            response.buildTransfer.metadata = [
                "os": "linux",
                "stage": "fssync",
                "mode": "json",
            ]
            response.buildTransfer.data = jsonData
            response.packetType = .buildTransfer(response.buildTransfer)
            sender.yield(response)
        } else {
            // Send empty tar for tar mode
            var response = ClientStream()
            response.buildID = buildID
            response.buildTransfer = BuildTransfer()
            response.buildTransfer.id = packet.id
            response.buildTransfer.source = packet.source
            response.buildTransfer.complete = true
            response.buildTransfer.direction = .outof
            response.buildTransfer.isDirectory = false
            response.buildTransfer.metadata = [
                "os": "linux",
                "stage": "fssync",
                "mode": "tar",
            ]
            response.buildTransfer.data = Data()
            response.packetType = .buildTransfer(response.buildTransfer)
            sender.yield(response)
        }
    }
    
    private func handleIO(
        _ io: IO,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        // Write the output to our terminal if not quiet
        if !config.quiet {
            if let handle = config.terminal?.handle {
                try handle.write(contentsOf: io.data)
            } else {
                // Fallback to stderr
                try FileHandle.standardError.write(contentsOf: io.data)
            }
        }
        
        // CRITICAL: Send terminal command response back to BuildKit
        // BuildKit waits for this response before continuing
        let cmdString = try SimpleTerminalCommand().json()
        var response = ClientStream()
        response.buildID = buildID
        response.command = .init()
        response.command.id = buildID
        response.command.command = cmdString
        sender.yield(response)
    }
    
    private func pullImage(reference: String, platform: Platform) async throws -> ImageDescription {
        // Normalize the image reference to include registry host
        var normalizedRef = reference
        if !reference.contains("/") {
            normalizedRef = "docker.io/library/\(reference)"
        } else if reference.split(separator: "/").count == 2 && !reference.contains(".") {
            normalizedRef = "docker.io/\(reference)"
        }
        
        // Check if image already exists
        let existingImages = try await imagesService.list()
        if let existing = existingImages.first(where: { $0.reference == normalizedRef || $0.reference == reference }) {
            logger.debug("Using existing image: \(normalizedRef)")
            return existing
        }
        
        // Pull the image
        logger.info("Pulling \(normalizedRef)...")
        let imageDescription = try await imagesService.pull(
            reference: normalizedRef,
            platform: platform,
            insecure: false,
            progressUpdate: { events in
                if !self.config.quiet {
                    for event in events {
                        if case .setDescription(let desc) = event {
                            self.logger.info("\(desc)")
                        }
                    }
                }
            }
        )
        
        try await imagesService.unpack(
            description: imageDescription,
            platform: platform,
            progressUpdate: nil
        )
        
        logger.info("Pulled \(normalizedRef)")
        
        return imageDescription
    }
}

// MARK: - Terminal Command

/// Simple terminal command for sending responses to BuildKit
/// Matches the structure from ContainerBuild/TerminalCommand.swift
private struct SimpleTerminalCommand: Codable {
    let commandType: String
    let code: String
    let rows: UInt16
    let cols: UInt16
    
    enum CodingKeys: String, CodingKey {
        case commandType = "command_type"
        case code
        case rows
        case cols
    }
    
    init() {
        self.commandType = "terminal"
        self.code = "ack"
        self.rows = 0
        self.cols = 0
    }
    
    func json() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        // CRITICAL: The command must be base64 encoded (without padding)
        return data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// MARK: - Errors

enum SandboxedBuilderError: Swift.Error, CustomStringConvertible, Equatable {
    case invalidContinuation
    case imageMissing
    case platformMissing
    case imageNotFound
    case imageNotInContentStore(String)
    case unknownPlatformForImage(String, String)
    case buildComplete
    case buildTimeout
    
    var description: String {
        switch self {
        case .invalidContinuation:
            return "Failed to create stream continuation"
        case .imageMissing:
            return "Image reference missing in metadata"
        case .platformMissing:
            return "Platform parameter missing in metadata"
        case .imageNotFound:
            return "Image not found in content store"
        case .imageNotInContentStore(let ref):
            return "Image not found in content store: \(ref)"
        case .unknownPlatformForImage(let platform, let ref):
            return "Platform \(platform) for image \(ref) not found"
        case .buildComplete:
            return "Build completed successfully"
        case .buildTimeout:
            return "Build timed out"
        }
    }
}
