//
//  ImageTransfer.swift
//  Containers
//
//  Represents an image transfer operation between the client and builder.
//

import Foundation
import ContainerizationOCI

/// Represents an image transfer during the build process.
public struct ImageTransfer: Sendable, Codable {
    
    /// Direction of the image transfer.
    public enum Direction: String, Sendable, Codable {
        case into
        case outof
    }
    
    public var id: String = ""
    public var tag: String = ""
    public var metadata: [String: String] = [:]
    public var complete: Bool = false
    public var direction: Direction = .into
    public var data: Data = Data()
    public var descriptor: Descriptor = Descriptor(mediaType: "", digest: "", size: 0)
    
    public init() {}
    
    // MARK: - Metadata Accessors
    
    public func stage() -> String? {
        self.metadata["stage"]
    }
    
    public func method() -> String? {
        self.metadata["method"]
    }
    
    public func ref() -> String? {
        self.metadata["ref"]
    }
    
    public func platform() throws -> Platform? {
        guard let platform = self.metadata["platform"] else {
            return nil
        }
        return try Platform(from: platform)
    }
    
    // MARK: - Convenience Initializer
    
    public init(id: String, digest: String, ref: String, platform: String, data: Data) throws {
        self.init()
        self.id = id
        self.tag = digest
        self.metadata = [
            "os": "linux",
            "stage": "resolver",
            "method": "/resolve",
            "ref": ref,
            "platform": platform,
        ]
        self.complete = true
        self.direction = .into
        self.data = data
    }
}
