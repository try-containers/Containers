//
//  Plugin.swift
//  Containers
//
//  Represents a container plugin that can be registered with the runtime.
//

import Foundation

/// Represents a container plugin.
public struct Plugin: Sendable {
    public var name: String
    public var binaryURL: URL
    
    public init(name: String, binaryURL: URL) {
        self.name = name
        self.binaryURL = binaryURL
    }
}
