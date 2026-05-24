//
//  BuildTypes.swift
//  Containers
//
//  Supporting types for the builder system.
//

import Foundation
import Containerization
import ContainerizationOCI
import NIO

/// Represents I/O data from the build process.
public struct IO: Sendable, Codable {
    public var data: Data
    
    public init(data: Data = Data()) {
        self.data = data
    }
}

/// Represents an error from the build process.
public struct BuildError: Sendable, Codable {
    public var message: String
    
    public init(message: String = "") {
        self.message = message
    }
}

/// Represents a command sent to/from the builder.
public struct BuildCommand: Sendable, Codable {
    public var id: String = ""
    public var command: String = ""
    
    public init() {}
}

// MARK: - Builder Configuration

extension Builder {
    /// Configuration for a build operation.
    public struct BuildConfig: Sendable {
        public var buildID: String
        public var contentStore: ContentStore
        public var buildArgs: [String]
        public var contextDir: String
        public var dockerfile: Data
        public var labels: [String]
        public var noCache: Bool
        public var platforms: [Platform]
        public var terminal: BuildTerminal?
        public var tags: [String]
        public var target: String
        public var quiet: Bool
        public var exports: [BuildExport]
        public var cacheIn: [String]
        public var cacheOut: [String]
        
        public init(
            buildID: String,
            contentStore: ContentStore,
            buildArgs: [String] = [],
            contextDir: String,
            dockerfile: Data,
            labels: [String] = [],
            noCache: Bool = false,
            platforms: [Platform] = [.current],
            terminal: BuildTerminal? = nil,
            tags: [String] = [],
            target: String = "",
            quiet: Bool = false,
            exports: [BuildExport] = [],
            cacheIn: [String] = [],
            cacheOut: [String] = []
        ) {
            self.buildID = buildID
            self.contentStore = contentStore
            self.buildArgs = buildArgs
            self.contextDir = contextDir
            self.dockerfile = dockerfile
            self.labels = labels
            self.noCache = noCache
            self.platforms = platforms
            self.terminal = terminal
            self.tags = tags
            self.target = target
            self.quiet = quiet
            self.exports = exports
            self.cacheIn = cacheIn
            self.cacheOut = cacheOut
        }
    }
    
    /// Represents a build export configuration.
    public struct BuildExport: Sendable {
        public var type: String
        public var destination: URL?
        public var additionalFields: [String: String]
        public var rawValue: String
        
        public init(
            type: String,
            destination: URL? = nil,
            additionalFields: [String: String] = [:],
            rawValue: String = ""
        ) {
            self.type = type
            self.destination = destination
            self.additionalFields = additionalFields
            self.rawValue = rawValue
        }
    }
    
    /// Terminal handle for build output.
    public struct BuildTerminal: Sendable {
        public var handle: FileHandle?
        
        public init(handle: FileHandle? = nil) {
            self.handle = handle
        }
    }
}

// MARK: - gRPC Protocol Types

/// Protocol for synchronous builder client operations.
public protocol BuilderClientProtocol: Sendable {}

/// Protocol for async builder client operations.
public protocol BuilderClientAsyncProtocol: Sendable {
    func info(_ request: InfoRequest, callOptions: CallOptions) async throws -> InfoResponse
    func performBuild(_ stream: AsyncStream<ClientStream>, callOptions: CallOptions) -> GRPCAsyncResponseStream<ServerStream>
}

/// Synchronous builder gRPC client.
public struct BuilderClient: BuilderClientProtocol, Sendable {
    public let channel: GRPCChannel
    
    public init(channel: GRPCChannel) {
        self.channel = channel
    }
}

/// Async builder gRPC client.
public struct BuilderClientAsync: BuilderClientAsyncProtocol, Sendable {
    public let channel: GRPCChannel
    
    public init(channel: GRPCChannel) {
        self.channel = channel
    }
    
    public func info(_ request: InfoRequest, callOptions: CallOptions) async throws -> InfoResponse {
        // Placeholder - actual gRPC call implementation
        return InfoResponse()
    }
    
    public func performBuild(_ stream: AsyncStream<ClientStream>, callOptions: CallOptions) -> GRPCAsyncResponseStream<ServerStream> {
        // Placeholder - actual gRPC call implementation
        return GRPCAsyncResponseStream()
    }
}

/// Request for builder info.
public struct InfoRequest: Sendable {
    public init() {}
}

/// Response from builder info.
public struct InfoResponse: Sendable {
    public init() {}
}

/// Options for gRPC calls.
public struct CallOptions: Sendable {
    public var timeLimit: TimeLimit?
    
    public init(timeLimit: TimeLimit? = nil) {
        self.timeLimit = timeLimit
    }
    
    public init(_ config: Builder.BuildConfig) throws {
        self.timeLimit = nil
    }
    
    public struct TimeLimit: Sendable {
        public let duration: Duration
        
        public static func timeout(_ duration: Duration) -> TimeLimit {
            TimeLimit(duration: duration)
        }
    }
}

/// Represents a gRPC channel.
public protocol GRPCChannel: Sendable {
    func close() -> EventLoopFuture<Void>
}

/// Async response stream from gRPC.
public struct GRPCAsyncResponseStream<T: Sendable>: AsyncSequence, Sendable {
    public typealias Element = T
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async throws -> T? {
            return nil
        }
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator()
    }
    
    public init() {}
}

/// gRPC client connection.
public final class ClientConnection: GRPCChannel, @unchecked Sendable {
    
    public struct Configuration: Sendable {
        public var target: ConnectionTarget
        public var eventLoopGroup: EventLoopGroup
        public var connectionIdleTimeout: TimeAmount = TimeAmount(.seconds(300))
        public var connectionKeepalive: KeepaliveConfig = KeepaliveConfig()
        public var connectionBackoff: BackoffConfig = BackoffConfig()
        public var callStartBehavior: CallStartBehavior = .fastFailure
        public var httpMaxFrameSize: Int = 16384
        public var maximumReceiveMessageLength: Int = 4194304
        public var httpTargetWindowSize: Int = 65535
        
        public static func `default`(target: ConnectionTarget, eventLoopGroup: EventLoopGroup) -> Configuration {
            Configuration(target: target, eventLoopGroup: eventLoopGroup)
        }
        
        public init(target: ConnectionTarget = .connectedSocket(0), eventLoopGroup: EventLoopGroup) {
            self.target = target
            self.eventLoopGroup = eventLoopGroup
        }
    }
    
    public enum ConnectionTarget: Sendable {
        case connectedSocket(Int32)
        case host(String, port: Int)
    }
    
    public struct KeepaliveConfig: Sendable {
        public var interval: TimeAmount
        public var timeout: TimeAmount
        public var permitWithoutCalls: Bool
        
        public init(
            interval: TimeAmount = TimeAmount(.seconds(300)),
            timeout: TimeAmount = TimeAmount(.seconds(200)),
            permitWithoutCalls: Bool = false
        ) {
            self.interval = interval
            self.timeout = timeout
            self.permitWithoutCalls = permitWithoutCalls
        }
    }
    
    public struct BackoffConfig: Sendable {
        public var initialBackoff: TimeInterval
        public var maximumBackoff: TimeInterval
        
        public init(
            initialBackoff: TimeInterval = 1,
            maximumBackoff: TimeInterval = 10
        ) {
            self.initialBackoff = initialBackoff
            self.maximumBackoff = maximumBackoff
        }
    }
    
    public enum CallStartBehavior: Sendable {
        case fastFailure
        case waitsForConnectivity
    }
    
    private let config: Configuration
    
    public init(configuration: Configuration) {
        self.config = configuration
    }
    
    public func close() -> EventLoopFuture<Void> {
        config.eventLoopGroup.next().makeSucceededVoidFuture()
    }
}

/// Time amount for gRPC configuration.
public struct TimeAmount: Sendable {
    public let duration: Duration
    
    public init(_ duration: Duration) {
        self.duration = duration
    }
}

// MARK: - Typealiases

/// Plugin loader placeholder.
public struct PluginLoader: Sendable {
    public init() {}
}
