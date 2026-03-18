//
//  ContainerRuntime+Prerequisites.swift
//  Containers
//
//  Prerequisites installation extension for ContainerRuntime.
//  Handles installation of init filesystem and default kernel.
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import ContainerizationOCI
import Containerization
import ContainerizationError
import ContainerizationArchive

extension ContainerRuntime {
    
    // MARK: - Prerequisites Installation
    
    /// Install system prerequisites (init image and kernel)
    internal func installPrerequisites() async throws {
        // Check and install init filesystem if needed
        let initExists = await initImageExists()
        if !initExists {
            Self.logger.info("Installing base container filesystem...")
            try await installInitialFilesystem()
        }
        
        // Check and install default kernel if needed
        let kernelExistsResult = await kernelExists()
        if !kernelExistsResult {
            Self.logger.info("Installing default kernel...")
            try await installDefaultKernel()
            Self.logger.info("Kernel installed")
        }
    }
    
    // MARK: - Private Helpers
    
    private func installInitialFilesystem() async throws {
        let initFsRef = DefaultsStore.get(key: .defaultInitImage)
        
        let service = try await getImagesService()
        
        let imageDescription = try await service.pull(
            reference: initFsRef,
            platform: .current,
            insecure: false,
            progressUpdate: { _ in }
        )
        
        try await service.unpack(
            description: imageDescription,
            platform: .current,
            progressUpdate: { _ in }
        )
    }
    
    private func installDefaultKernel() async throws {
        // Get kernel URL and binary path from DefaultsStore (same as Apple Container CLI)
        let defaultKernelURL = DefaultsStore.get(key: .defaultKernelURL)
        let defaultKernelBinaryPath = DefaultsStore.get(key: .defaultKernelBinaryPath)
        
        Self.logger.info("Starting kernel installation from: \(defaultKernelURL)")
        Self.logger.info("Kernel binary path in archive: \(defaultKernelBinaryPath)")
        
        guard let sourceURL = URL(string: defaultKernelURL) else {
            throw ContainerizationError(.invalidArgument, message: "Invalid kernel URL: \(defaultKernelURL)")
        }
        
        // Create temp directory for download and extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Download the kernel tar file
        let tarFile = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        Self.logger.info("Downloading from: \(sourceURL) to: \(tarFile.path)")
        
        let (tempDownloadURL, response) = try await URLSession.shared.download(from: sourceURL)
        
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.info("Download response status: \(httpResponse.statusCode)")
            guard httpResponse.statusCode == 200 else {
                throw ContainerizationError(.internalError, message: "Failed to download kernel: HTTP \(httpResponse.statusCode)")
            }
        }
        
        // Move downloaded file to our temp directory
        try FileManager.default.moveItem(at: tempDownloadURL, to: tarFile)
        
        Self.logger.info("Downloaded to: \(tarFile.path)")
        
        // Extract the kernel using ArchiveReader (same as Apple Container CLI)
        let kernelFile = try extractKernelFromArchive(tarFile: tarFile, kernelPath: defaultKernelBinaryPath, tempDir: tempDir)
        
        // Use the KernelService to install the kernel (creates symlink, etc.)
        let service = try await getKernelService()
        try await service.installKernel(kernelFile: kernelFile, platform: .current, force: true)
        
        Self.logger.info("Kernel installed successfully")
    }
    
    /// Extract kernel file from archive using ArchiveReader (same approach as Apple Container CLI)
    private func extractKernelFromArchive(tarFile: URL, kernelPath: String, tempDir: URL) throws -> URL {
        Self.logger.info("Extracting kernel from archive: \(tarFile.path)")
        Self.logger.info("Looking for: \(kernelPath)")
        
        var archiveReader = try ArchiveReader(file: tarFile)
        var (entry, data) = try archiveReader.extractFile(path: kernelPath)
        
        // If the target file is a symlink, get the data for the actual file
        if entry.fileType == .symbolicLink, let symlinkRelative = entry.symlinkTarget {
            Self.logger.info("Kernel is a symlink to: \(symlinkRelative)")
            // Reopen the archive to traverse from the beginning
            archiveReader = try ArchiveReader(file: tarFile)
            
            let symlinkTarget = URL(filePath: kernelPath).deletingLastPathComponent().appending(path: symlinkRelative)
            let resolvedPath = symlinkTarget.standardized.relativePath
            
            Self.logger.info("Resolved symlink path: \(resolvedPath)")
            
            let (_, targetData) = try archiveReader.extractFile(path: resolvedPath)
            
            data = targetData
        }
        
        // Write the kernel to temp directory
        let fileName = URL(filePath: kernelPath).lastPathComponent
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try data.write(to: fileURL, options: .atomic)
        
        Self.logger.info("Extracted kernel to: \(fileURL.path), size: \(data.count) bytes")
        
        return fileURL
    }
    
    private func initImageExists() async -> Bool {
        guard let service = try? await getImagesService() else {
            return false
        }
        
        do {
            let images = try await service.list()
            let initFsRef = DefaultsStore.get(key: .defaultInitImage)
            
            return images.contains { $0.reference == initFsRef }
        } catch {
            return false
        }
    }
    
    private func kernelExists() async -> Bool {
        guard let service = try? await getKernelService() else {
            return false
        }
        
        do {
            _ = try await service.getDefaultKernel(platform: .current)
            
            return true
        } catch {
            Self.logger.warning("Failed to check kernel: \(error)")
            
            return false
        }
    }
}
