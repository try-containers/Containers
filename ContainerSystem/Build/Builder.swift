//
//  Builder.swift
//  Containers
//
//  Sandboxed version of Builder that implements build protocol without XPC dependencies
//
//  Created by Axel Martinez on 2026/02/09.
//

import Containerization
import ContainerizationArchive
import ContainerizationError
import ContainerizationOCI
import ContainerizationOS
import CryptoKit
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Logging
import NIO
import NIOCore
import NIOHPACK
import NIOHTTP2
import NIOPosix

/// Builder that uses ImagesService instead of XPC-based ClientImage
public struct Builder: Sendable {
    public static let builderContainerId = "buildkit"

    let client:
        Com_Apple_Container_Build_V1_Builder.Client<
            HTTP2ClientTransport.WrappedChannel
        >
    let grpcClient: GRPCClient<HTTP2ClientTransport.WrappedChannel>
    let group: EventLoopGroup
    let builderShimSocket: FileHandle
    let clientTask: Task<Void, any Swift.Error>
    let imagesService: ImagesService
    let contentStore: ContentStore

    private let logger: Logger

    internal init(
        socket: FileHandle,
        group: EventLoopGroup,
        imagesService: ImagesService,
        contentStore: ContentStore
    ) throws {
        try socket.setSendBufSize(4 << 20)
        try socket.setRecvBufSize(2 << 20)

        let channel = try ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture(withResultOf: {
                    try channel.pipeline.syncOperations.addHandler(
                        HTTP2ConnectBufferingHandler()
                    )
                })
            }
            .withConnectedSocket(socket.fileDescriptor)
            .wait()

        let transport = HTTP2ClientTransport.WrappedChannel.wrapping(
            channel: channel
        )
        let grpcClient = GRPCClient(transport: transport)

        self.grpcClient = grpcClient
        self.client = Com_Apple_Container_Build_V1_Builder.Client(
            wrapping: grpcClient
        )
        self.group = group
        self.builderShimSocket = socket
        self.imagesService = imagesService
        self.contentStore = contentStore

        var logger = Logger(label: "app.containers.sandboxed-builder")
        logger.logLevel = .info
        self.logger = logger
        self.clientTask = Task {
            do {
                try await grpcClient.runConnections()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RPCError where error.code == .unavailable {
                logger.debug("gRPC connection closed: \(error)")
                throw error
            } catch {
                logger.error("gRPC client connection error: \(error)")
                throw error
            }
        }
    }

    public func info() async throws -> InfoResponse {
        var options = CallOptions.defaults
        options.timeout = .seconds(30)
        return try await self.client.info(InfoRequest(), options: options)
    }

    /// Perform a sandboxed build using custom pipeline that handles image resolution
    public func build(_ config: Builder.BuildConfig) async throws {
        let logger = Logger(label: "app.containers.sandboxed-builder.build")
        logger.info(
            "SandboxedBuilder.build() called with buildID: \(config.buildID)"
        )

        var continuation: AsyncStream<ClientStream>.Continuation?
        let reqStream = AsyncStream<ClientStream> {
            (cont: AsyncStream<ClientStream>.Continuation) in
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
        logger.info(
            "Build config: buildID=\(config.buildID), contextDir=\(config.contextDir)"
        )
        logger.info(
            "Build config: dockerfile size=\(config.dockerfile.count) bytes, tags=\(config.tags)"
        )
        logger.info(
            "Build config: platforms=\(config.platforms.map { $0.description }), target=\(config.target)"
        )
        logger.info("Build config: exports=\(config.exports.map { $0.type })")

        logger.info("Initializing sandboxed build pipeline")
        let pipeline = BuildPipeline(
            config: config,
            imagesService: self.imagesService,
            contentStore: self.contentStore
        )

        logger.info("Starting pipeline execution")

        // Start a background task to log progress
        let progressTask = Task {
            try? await Task.sleep(for: .seconds(30))
            logger.warning(
                "Pipeline has been running for 30 seconds without completion"
            )
            try? await Task.sleep(for: .seconds(30))
            logger.error(
                "Pipeline has been running for 60 seconds - BuildKit may not be responding"
            )
        }

        do {
            try await self.client.performBuild(
                metadata: try Self.buildMetadata(config),
                options: .defaults,
                requestProducer: { writer in
                    for await message in reqStream {
                        try await writer.write(message)
                    }
                },
                onResponse: { response in
                    try await pipeline.run(
                        sender: continuation,
                        receiver: response.messages
                    )
                }
            )
            progressTask.cancel()
            grpcClient.beginGracefulShutdown()
            clientTask.cancel()
            try await group.shutdownGracefully()
            logger.info("Build completed successfully")
        } catch {
            progressTask.cancel()

            // Check if this is the normal build complete signal
            if let builderError = error as? SandboxedBuilderError,
                builderError == .buildComplete
            {
                grpcClient.beginGracefulShutdown()
                clientTask.cancel()
                try await group.shutdownGracefully()
                logger.info("Build completed successfully")
                return
            }

            logger.error("Pipeline execution failed: \(error)")
            grpcClient.beginGracefulShutdown()
            clientTask.cancel()
            try await group.shutdownGracefully()
            throw error
        }
    }

    static func buildMetadata(_ config: Builder.BuildConfig) throws -> Metadata {
        var metadata = Metadata()
        metadata.addString(config.buildID, forKey: "build-id")
        metadata.addString(
            URL(fileURLWithPath: config.contextDir).path(percentEncoded: false),
            forKey: "context"
        )
        metadata.addString(
            config.dockerfile.base64EncodedString(),
            forKey: "dockerfile"
        )
        metadata.addString(config.terminal != nil ? "tty" : "plain", forKey: "progress")
        metadata.addString(config.target, forKey: "target")

        for tag in config.tags {
            metadata.addString(tag, forKey: "tag")
        }
        for platform in config.platforms {
            metadata.addString(platform.description, forKey: "platforms")
        }
        if config.noCache {
            metadata.addString("", forKey: "no-cache")
        }
        for label in config.labels {
            metadata.addString(label, forKey: "labels")
        }
        for buildArg in config.buildArgs {
            metadata.addString(buildArg, forKey: "build-args")
        }
        for output in config.exports {
            metadata.addString(try output.stringValue, forKey: "outputs")
        }
        for cacheIn in config.cacheIn {
            metadata.addString(cacheIn, forKey: "cache-in")
        }
        for cacheOut in config.cacheOut {
            metadata.addString(cacheOut, forKey: "cache-out")
        }

        return metadata
    }
}

// MARK: - Build Pipeline

/// Custom build pipeline that uses ImagesService for image resolution instead of XPC
private actor BuildPipeline {
    let config: Builder.BuildConfig
    let imagesService: ImagesService
    let contentStore: ContentStore
    let logger: Logger

    init(
        config: Builder.BuildConfig,
        imagesService: ImagesService,
        contentStore: ContentStore
    ) {
        self.config = config
        self.imagesService = imagesService
        self.contentStore = contentStore
        var logger = Logger(label: "app.containers.sandboxed-pipeline")
        logger.logLevel = .debug
        self.logger = logger
    }

    func run<Receiver: AsyncSequence>(
        sender: AsyncStream<ClientStream>.Continuation,
        receiver: Receiver
    ) async throws where Receiver.Element == ServerStream {
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
                logger.debug(
                    "Packet #\(packetCount): ImageTransfer(stage:\(transfer.stage() ?? "nil"), method:\(transfer.method() ?? "nil"))"
                )
            case .buildTransfer(let transfer):
                logger.debug(
                    "Packet #\(packetCount): BuildTransfer(stage:\(transfer.metadata["stage"] ?? "nil"), method:\(transfer.metadata["method"] ?? "nil"))"
                )
            case .io(let io):
                if let message = String(data: io.data, encoding: .utf8),
                    !message.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                {
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
                try await handleImageTransfer(
                    imageTransfer,
                    sender: sender,
                    buildID: packet.buildID
                )
            } else if let buildTransfer = packet.getBuildTransfer() {
                try await handleBuildTransfer(
                    buildTransfer,
                    sender: sender,
                    buildID: packet.buildID
                )
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
            try await handleResolverRequest(
                imageTransfer,
                sender: sender,
                buildID: buildID
            )
            return
        }

        // Handle content-store requests
        if stage == "content-store" {
            try await handleContentStoreRequest(
                imageTransfer,
                sender: sender,
                buildID: buildID
            )
            return
        }

        logger.debug(
            "Skipping ImageTransfer(stage=\(stage ?? "nil"), method=\(method ?? "nil"))"
        )
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

        logger.info(
            "Resolving image: \(ref) for platform: \(platform.description)"
        )

        let imageDescription = try await pullImage(
            reference: ref,
            platform: platform
        )

        guard
            let indexContent: Content = try await contentStore.get(
                digest: imageDescription.digest
            )
        else {
            throw SandboxedBuilderError.imageNotFound
        }
        let index: Index = try indexContent.decode()

        for manifest in index.manifests {
            if manifest.platform == platform {
                guard
                    let manifestContent: Content = try await contentStore.get(
                        digest: manifest.digest
                    )
                else {
                    continue
                }
                let manifestData: Manifest = try manifestContent.decode()

                guard
                    let ociImage: ContainerizationOCI.Image =
                        try await contentStore.get(
                            digest: manifestData.config.digest
                        )
                else {
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

        throw SandboxedBuilderError.unknownPlatformForImage(
            platform.description,
            ref
        )
    }

    private func handleContentStoreRequest(
        _ imageTransfer: ImageTransfer,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let method = imageTransfer.metadata["method"]

        switch method {
        case "/containerd.services.content.v1.Content/Info":
            try await handleContentStoreInfo(
                imageTransfer,
                sender: sender,
                buildID: buildID
            )
        case "/containerd.services.content.v1.Content/ReaderAt":
            try await handleContentStoreReaderAt(
                imageTransfer,
                sender: sender,
                buildID: buildID
            )
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
        guard let data = try descriptor.data(offset: offset, length: length)
        else {
            logger.error(
                "Failed to read data from content store: digest=\(digest), offset=\(offset), length=\(length)"
            )
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

        logger.info(
            "BuildTransfer: stage=\(stage ?? "nil"), direction=\(direction), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)"
        )

        switch stage {
        case "fssync":
            // Handle build context file sync
            try await handleFSSyncTransfer(
                buildTransfer,
                sender: sender,
                buildID: buildID
            )
        case "export", nil:
            // Handle export file write - BuildKit is trying to write the export tar
            logger.info("Handling export transfer")
            try await handleExportTransfer(
                buildTransfer,
                sender: sender,
                buildID: buildID
            )
        default:
            logger.warning(
                "Ignoring BuildTransfer with unknown stage: \(stage ?? "unknown")"
            )
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
            try await handleFSSyncRead(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
        case "Info":
            try await handleFSSyncInfo(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
        case "Walk":
            try await handleFSSyncWalk(
                buildTransfer,
                contextDir: contextDir,
                sender: sender,
                buildID: buildID
            )
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

        logger.info(
            "Export transfer: direction=\(buildTransfer.direction), complete=\(buildTransfer.complete), source=\(buildTransfer.source), dataSize=\(buildTransfer.data.count)"
        )

        guard let exportPath = exportDestination(for: buildTransfer) else {
            logger.error(
                "Could not resolve export destination for: \(buildTransfer.source)"
            )
            return
        }

        logger.info("Writing export data to: \(exportPath.path)")

        // Create parent directory if needed
        let parentDir = exportPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

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

    private func exportDestination(for buildTransfer: BuildTransfer) -> URL? {
        let sourceLastPathComponent = URL(fileURLWithPath: buildTransfer.source)
            .lastPathComponent
        let destinations = config.exports.compactMap(\.destination)

        if let matchingDestination = destinations.first(where: {
            $0.lastPathComponent == sourceLastPathComponent
        }) {
            return matchingDestination
        }

        guard destinations.count == 1 else {
            return nil
        }

        return destinations[0]
    }

    private func handleFSSyncRead(
        _ packet: BuildTransfer,
        contextDir: URL,
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let path = contextDir.appendingPathComponent(packet.source)
            .standardizedFileURL

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
                    data = fileData.subdata(
                        in: start..<min(end, fileData.count)
                    )
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
        let path = contextDir.appendingPathComponent(packet.source)
            .standardizedFileURL

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
            let attrs = try? FileManager.default.attributesOfItem(
                atPath: path.path
            )
        {
            if let size = attrs[.size] as? UInt64 {
                response.buildTransfer.metadata["size"] = String(size)
            }
            if let mode = attrs[.posixPermissions] as? NSNumber {
                response.buildTransfer.metadata["mode"] = String(
                    mode.uint32Value
                )
            }
            if let modDate = attrs[.modificationDate] as? Date {
                let formatter = ISO8601DateFormatter()
                response.buildTransfer.metadata["modified_at"] =
                    formatter.string(from: modDate)
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
        let mode = packet.metadata["mode"] ?? "json"
        let followPaths =
            packet.metadata["followpaths"]?.split(separator: ",").map(
                String.init
            ) ?? []
        logger.info(
            "FSSync walk: contextDir=\(contextDir.path), mode=\(mode), followpaths=\(followPaths)"
        )

        let matchedFiles = try matchPaths(
            contextDir: contextDir,
            followPaths: followPaths
        )
        logger.info(
            "FSSync walk matched \(matchedFiles.count) files: \(matchedFiles.prefix(5).map { $0.relativePath })"
        )

        if mode == "tar" {
            try await sendTarWalk(
                packet: packet,
                contextDir: contextDir,
                files: matchedFiles,
                sender: sender,
                buildID: buildID
            )
        } else {
            try sendJSONWalk(
                packet: packet,
                contextDir: contextDir,
                files: matchedFiles,
                sender: sender,
                buildID: buildID
            )
        }
    }

    private struct MatchedFile {
        let url: URL
        let relativePath: String
        let isDirectory: Bool
    }

    private func matchPaths(contextDir: URL, followPaths: [String]) throws
        -> [MatchedFile]
    {
        let fm = FileManager.default
        let root = contextDir.standardizedFileURL
        var results: [MatchedFile] = []

        for pattern in followPaths {
            let candidate = root.appendingPathComponent(pattern)
            if fm.fileExists(atPath: candidate.path) {
                let attrs = try fm.attributesOfItem(atPath: candidate.path)
                let isDir =
                    (attrs[.type] as? FileAttributeType) == .typeDirectory
                results.append(
                    MatchedFile(
                        url: candidate,
                        relativePath: pattern,
                        isDirectory: isDir
                    )
                )
            }
        }

        results.sort { $0.relativePath < $1.relativePath }
        return results
    }

    private func sendJSONWalk(
        packet: BuildTransfer,
        contextDir: URL,
        files: [MatchedFile],
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) throws {
        let fm = FileManager.default
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let fileInfos = try files.map { match -> FSSyncFileInfo in
            let attrs = try fm.attributesOfItem(atPath: match.url.path)
            let size = (attrs[.size] as? UInt64) ?? 0
            let mode =
                (attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            let target: String = {
                guard
                    (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
                else { return "" }
                return (try? fm.destinationOfSymbolicLink(atPath: match.url.path))
                    ?? ""
            }()
            return FSSyncFileInfo(
                name: match.relativePath,
                modTime: formatter.string(from: modDate),
                mode: mode,
                size: size,
                isDir: match.isDirectory,
                uid: 0,
                gid: 0,
                target: target
            )
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
            "mode": "json",
        ]
        response.buildTransfer.data = try JSONEncoder().encode(fileInfos)
        response.packetType = .buildTransfer(response.buildTransfer)
        sender.yield(response)
    }

    private func sendTarWalk(
        packet: BuildTransfer,
        contextDir: URL,
        files: [MatchedFile],
        sender: AsyncStream<ClientStream>.Continuation,
        buildID: String
    ) async throws {
        let tarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: tarURL) }

        let hash = try writeTar(
            files: files,
            contextDir: contextDir,
            destination: tarURL
        )
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        logger.info(
            "FSSync tar walk created \(tarURL.lastPathComponent) hash=\(hashString)"
        )

        // Send header packet with hash (no data yet)
        var header = BuildTransfer()
        header.id = packet.id
        header.source = tarURL.path
        header.complete = false
        header.direction = .outof
        header.metadata = [
            "os": "linux",
            "stage": "fssync",
            "mode": "tar",
            "hash": hashString,
        ]
        var headerResp = ClientStream()
        headerResp.buildID = buildID
        headerResp.buildTransfer = header
        headerResp.packetType = .buildTransfer(header)
        sender.yield(headerResp)

        // Stream tar file in chunks
        let chunkSize = 1 << 20  // 1 MiB
        guard let handle = try? FileHandle(forReadingFrom: tarURL) else {
            throw SandboxedBuilderError.imageMissing
        }
        defer { try? handle.close() }

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            var part = BuildTransfer()
            part.id = packet.id
            part.source = tarURL.path
            part.complete = false
            part.direction = .outof
            part.metadata = [
                "os": "linux",
                "stage": "fssync",
                "mode": "tar",
            ]
            part.data = chunk

            var partResp = ClientStream()
            partResp.buildID = buildID
            partResp.buildTransfer = part
            partResp.packetType = .buildTransfer(part)
            sender.yield(partResp)
        }

        // Final packet (complete=true, no data)
        var done = BuildTransfer()
        done.id = packet.id
        done.source = tarURL.path
        done.complete = true
        done.direction = .outof
        done.metadata = [
            "os": "linux",
            "stage": "fssync",
            "mode": "tar",
        ]
        var doneResp = ClientStream()
        doneResp.buildID = buildID
        doneResp.buildTransfer = done
        doneResp.packetType = .buildTransfer(done)
        sender.yield(doneResp)
    }

    private func writeTar(
        files: [MatchedFile],
        contextDir: URL,
        destination: URL
    ) throws -> SHA256.Digest {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)

        let config = ArchiveWriterConfiguration(
            format: .paxRestricted,
            filter: .none
        )
        let writer = try ArchiveWriter(configuration: config)
        try writer.open(file: destination)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hasher = SHA256()

        for match in files {
            let attrs = try fm.attributesOfItem(atPath: match.url.path)
            let entry = WriteEntry()
            entry.path = match.relativePath

            if let fileType = attrs[.type] as? FileAttributeType {
                switch fileType {
                case .typeDirectory:
                    entry.fileType = .directory
                case .typeSymbolicLink:
                    entry.fileType = .symbolicLink
                    entry.symlinkTarget =
                        (try? fm.destinationOfSymbolicLink(
                            atPath: match.url.path
                        )) ?? ""
                case .typeRegular:
                    entry.fileType = .regular
                default:
                    continue
                }
            }
            if let perms = attrs[.posixPermissions] as? NSNumber {
                #if os(macOS)
                entry.permissions = perms.uint16Value
                #else
                entry.permissions = perms.uint32Value
                #endif
            }
            if let size = attrs[.size] as? UInt64 {
                entry.size = Int64(size)
            }
            entry.owner = 0
            entry.group = 0
            if let modDate = attrs[.modificationDate] as? Date {
                entry.modificationDate = modDate
            }

            hasher.update(data: try encoder.encode(entry))

            if entry.fileType == .regular {
                let data = try Data(contentsOf: match.url)
                hasher.update(data: data)
                try writer.writeEntry(entry: entry, data: data)
            } else {
                try writer.writeEntry(entry: entry, data: nil)
            }
        }

        try writer.finishEncoding()
        return hasher.finalize()
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

    private func pullImage(reference: String, platform: Platform) async throws
        -> ImageDescription
    {
        let normalizedRef = try ClientImage.normalizeReference(reference)

        // Check if image already exists
        let existingImages = try await imagesService.list()
        if let existing = existingImages.first(where: {
            $0.reference == normalizedRef || $0.reference == reference
        }) {
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
                // Progress events are string-based (e.g., "add-items", "add-size")
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
        return data.base64EncodedString().trimmingCharacters(
            in: CharacterSet(charactersIn: "=")
        )
    }
}

private struct FSSyncFileInfo: Codable {
    let name: String
    let modTime: String
    let mode: UInt32
    let size: UInt64
    let isDir: Bool
    let uid: UInt32
    let gid: UInt32
    let target: String
}

extension WriteEntry: @retroactive Encodable {
    enum CodingKeys: String, CodingKey {
        case path
        case fileType
        case size
        case permissions
        case owner
        case group
        case symlinkTarget
        case hardlink
        case creationDate
        case modificationDate
        case contentAccessDate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fileType.rawValue, forKey: .fileType)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encodeIfPresent(symlinkTarget, forKey: .symlinkTarget)
        try container.encodeIfPresent(hardlink, forKey: .hardlink)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encodeIfPresent(contentAccessDate, forKey: .contentAccessDate)
    }
}

extension FileHandle {
    @discardableResult
    func setSendBufSize(_ bytes: Int) throws -> Int {
        try setSockOpt(
            level: SOL_SOCKET,
            name: SO_SNDBUF,
            value: bytes
        )
        return bytes
    }

    @discardableResult
    func setRecvBufSize(_ bytes: Int) throws -> Int {
        try setSockOpt(
            level: SOL_SOCKET,
            name: SO_RCVBUF,
            value: bytes
        )
        return bytes
    }

    private func setSockOpt(level: Int32, name: Int32, value: Int) throws {
        var socketValue = Int32(value)
        let result = withUnsafePointer(to: &socketValue) { pointer -> Int32 in
            pointer.withMemoryRebound(
                to: UInt8.self,
                capacity: MemoryLayout<Int32>.size
            ) { rawPointer in
                setsockopt(
                    self.fileDescriptor,
                    level,
                    name,
                    rawPointer,
                    socklen_t(MemoryLayout<Int32>.size)
                )
            }
        }

        if result == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
    }
}

/// Buffers incoming bytes until the gRPC HTTP/2 pipeline is configured.
private final class HTTP2ConnectBufferingHandler:
    ChannelDuplexHandler, RemovableChannelHandler
{
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var removalScheduled = false
    private var bufferedReads: [NIOAny] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        bufferedReads.append(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {}

    func flush(context: ChannelHandlerContext) {
        if !removalScheduled {
            removalScheduled = true
            context.eventLoop.assumeIsolatedUnsafeUnchecked().execute {
                context.pipeline.syncOperations.removeHandler(self, promise: nil)
            }
        }
        context.flush()
    }

    func removeHandler(
        context: ChannelHandlerContext,
        removalToken: ChannelHandlerContext.RemovalToken
    ) {
        var didRead = false
        while !bufferedReads.isEmpty {
            context.fireChannelRead(bufferedReads.removeFirst())
            didRead = true
        }
        if didRead {
            context.fireChannelReadComplete()
        }
        context.leavePipeline(removalToken: removalToken)
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
