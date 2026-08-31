//
//  BuildTypes.swift
//  Containers
//
//  Supporting types for the builder system.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation

// MARK: - Builder Configuration

extension Builder {
    /// Configuration for a build operation.
    public struct BuildConfig: Sendable {
        public var id: String
        public var contentStore: ContentStore
        public var args: [String]
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
        public var statusUpdate: (@Sendable (String) async -> Void)?

        public init(
            id: String,
            contentStore: ContentStore,
            args: [String] = [],
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
            cacheOut: [String] = [],
            statusUpdate: (@Sendable (String) async -> Void)? = nil
        ) {
            self.id = id
            self.contentStore = contentStore
            self.args = args
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
            self.statusUpdate = statusUpdate
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

        public var stringValue: String {
            get throws {
                var components = ["type=\(type)"]

                switch type {
                case "oci", "tar", "local":
                    break
                default:
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "Unsupported build output type: \(type)"
                    )
                }

                for (key, value) in additionalFields {
                    components.append("\(key)=\(value)")
                }

                return components.joined(separator: ",")
            }
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
