//
//  SystemManager.swift
//  Containers
//
//  Public API for system lifecycle management
//  UI layer uses this to start/stop the container system
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Observation

/// Public system manager for controlling container system lifecycle
/// This is the main API exposed to the UI layer for system control
@Observable
@MainActor
public final class SystemManager {

    internal let runtime: ContainerRuntime

    /// Public observable state
    public var isRunning: Bool { runtime.isRunning }
    public var isStarting: Bool { runtime.isStarting }
    public var isStopping: Bool { runtime.isStopping }
    public var startupError: Error? { runtime.startupError }

    /// System status for UI
    public enum SystemStatus: Equatable {
        case notStarted
        case starting
        case running
        case stopping
        case failed
    }

    public var systemStatus: SystemStatus {
        switch runtime.systemStatus {
        case .notStarted: return .notStarted
        case .starting: return .starting
        case .running: return .running
        case .stopping: return .stopping
        case .failed: return .failed
        }
    }

    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    internal init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
    }
    #endif

    // MARK: - Lifecycle Methods

    /// Start the container system.
    /// - Parameter appRoot: Root directory for container data.
    /// - Throws: An error if the runtime cannot initialize prerequisites, storage, services, or networking.
    public func start(appRoot: URL) async throws {
        try await runtime.start(appRoot: appRoot)
    }

    /// Stop the container system
    public func stop() async throws {
        try await runtime.stop()
    }
}
