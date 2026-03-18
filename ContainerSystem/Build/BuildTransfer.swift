//
//  BuildTransfer.swift
//  Containers
//
//  Represents a build context file transfer between host and builder.
//

import Foundation

/// Represents a file transfer during the build process.
public struct BuildTransfer: Sendable, Codable {
    
    /// Direction of the transfer.
    public enum Direction: String, Sendable, Codable {
        case into
        case outof
    }
    
    public var id: String = ""
    public var source: String = ""
    public var complete: Bool = false
    public var direction: Direction = .into
    public var isDirectory: Bool = false
    public var metadata: [String: String] = [:]
    public var data: Data = Data()
    
    public init() {}
}
