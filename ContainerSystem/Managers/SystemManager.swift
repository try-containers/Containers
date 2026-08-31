//
//  SystemManager.swift
//  Containers
//
//  System lifecycle management
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import Logging
import Observation

/// Public system manager for controlling container system lifecycle
/// This is the main API exposed to the UI layer for system control
@Observable
@MainActor
public final class SystemManager {

    let runtime: ContainerRuntime
    private let logger: Logger

    public var startupError: (any Error)? { runtime.startupError }

    /// System status for UI
    public enum SystemStatus: Equatable {
        case notStarted
        case starting
        case running
        case stopping
        case failed
    }

    public var status: SystemStatus {
        if runtime.isStopping { return .stopping }
        if runtime.isStarting { return .starting }
        if runtime.isRunning { return .running }
        if runtime.startupError != nil { return .failed }
        return .notStarted
    }

    /// Observable state for progress while the system installs what a first
    /// run needs. This mirrors the runtime's progress reporter.
    public var progress: ProgressReporter {
        runtime.progress
    }

    /// Public initializer - creates instance referencing shared runtime
    public init() {
        self.runtime = ContainerRuntime.shared
        self.logger = Logger(label: "app.containers.manager.system")
    }

    #if DEBUG
    /// Internal initializer for testing - allows injection of test runtime
    init(testRuntime: ContainerRuntime) {
        self.runtime = testRuntime
        self.logger = Logger(label: "app.containers.manager.system.test")
    }
    #endif

    // MARK: - Lifecycle Methods

    /// Start the container system.
    /// - Parameter appRoot: Root directory for container data.
    /// - Throws: An error if the runtime cannot initialize prerequisites, storage, services, or networking.
    public func start(appRoot: URL) async throws {
        logger.info("Starting system", metadata: ["appRoot": "\(appRoot.path)"])
        try await runtime.start(appRoot: appRoot)
    }

    /// Stop the container system
    public func stop() async throws {
        logger.info("Stopping system")
        try await runtime.stop()
    }
}
