//
//  ContainerOptions.swift
//  Containers
//
//  Local implementation of container create/stop options (replaces ContainerResource types)
//

import Foundation

/// Options for creating a container.
public struct ContainerCreateOptions: Sendable, Codable {
    public var autoRemove: Bool
    
    public init(autoRemove: Bool = false) {
        self.autoRemove = autoRemove
    }
}

/// Options for stopping a container.
public struct ContainerStopOptions: Sendable, Codable {
    public var timeoutInSeconds: Int32
    public var signal: Int32
    
    public init(timeoutInSeconds: Int32 = 10, signal: Int32 = SIGTERM) {
        self.timeoutInSeconds = timeoutInSeconds
        self.signal = signal
    }
    
    /// Default stop options (SIGTERM with 10 second timeout).
    public static let `default` = ContainerStopOptions()
}
