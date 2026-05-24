//
//  KernelService.swift
//  Containers
//
//  Manages kernel binaries for container VMs.
//
//  Created by Axel on 17/3/26.
//

import Foundation
import Containerization
import ContainerizationError
import Logging

/// Service for managing Linux kernel binaries used by container VMs.
internal actor KernelService {
    
    private let log: Logger
    private let kernelsRoot: URL
    
    internal init(log: Logger, appRoot: URL) throws {
        self.log = log
        self.kernelsRoot = appRoot.appendingPathComponent("kernels")
        
        try FileManager.default.createDirectory(at: kernelsRoot, withIntermediateDirectories: true)
    }
    
    /// Get the default kernel for the given platform.
    internal func getDefaultKernel(platform: SystemPlatform) async throws -> Kernel {
        let kernelPath = kernelsRoot.appendingPathComponent("default-\(platform.architecture.rawValue)")
        
        guard FileManager.default.fileExists(atPath: kernelPath.path) else {
            throw ContainerizationError(.notFound, message: "Default kernel not found for \(platform.architecture.rawValue)")
        }
        
        return Kernel(path: kernelPath, platform: platform)
    }
    
    /// Install a kernel binary for the given platform.
    internal func installKernel(kernelFile: URL, platform: SystemPlatform, force: Bool = false) async throws {
        let destination = kernelsRoot.appendingPathComponent("default-\(platform.architecture.rawValue)")
        
        if FileManager.default.fileExists(atPath: destination.path) {
            if force {
                try FileManager.default.removeItem(at: destination)
            } else {
                log.info("Kernel already installed for \(platform.architecture.rawValue), skipping")
                return
            }
        }
        
        try FileManager.default.copyItem(at: kernelFile, to: destination)
        
        log.info("Kernel installed at \(destination.path)")
    }
}
