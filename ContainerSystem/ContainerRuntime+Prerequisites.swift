//
//  ContainerRuntime+Prerequisites.swift
//  Containers
//
//  Prerequisites installation extension for ContainerRuntime.
//  Handles installation of init filesystem and default kernel.
//
//  Created by Axel Martinez on 2026/02/08.
//

import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation

extension ContainerRuntime {

    // MARK: - Prerequisites Installation

    /// Install system prerequisites (init image and kernel)
    func installPrerequisites() async throws {
        let initExists = await initImageExists()
        let kernelExistsResult = await kernelExists()

        // What a first run has to fetch is known before it starts, so the
        // steps count against what will actually be done.
        let steps = (initExists ? 0 : 2) + (kernelExistsResult ? 0 : 2)

        guard steps > 0 else { return }

        progress.begin(totalTasks: steps)

        defer {
            progress.finish()
        }

        if !initExists {
            logger.info("Installing base container filesystem...")
            try await installInitialFilesystem()
        }

        if !kernelExistsResult {
            logger.info("Installing default kernel...")
            try await installDefaultKernel()
            logger.info("Kernel installed")
        }
    }

    // MARK: - Private Helpers

    private func installInitialFilesystem() async throws {
        let initFsRef = DefaultsStore.get(key: .defaultInitImage)

        let service = try await getImagesService()

        progress.step("Fetching init image", itemsName: "blobs")
        let imageDescription = try await service.pull(
            reference: initFsRef,
            platform: .current,
            insecure: false,
            progressUpdate: progress.handler()
        )

        progress.step("Unpacking init image", itemsName: "entries")
        try await service.unpack(
            description: imageDescription,
            platform: .current,
            progressUpdate: progress.handler()
        )
    }

    private func installDefaultKernel() async throws {
        // Get kernel URL and binary path from DefaultsStore (same as Apple Container CLI)
        let defaultKernelURL = DefaultsStore.get(key: .defaultKernelURL)
        let defaultKernelBinaryPath = DefaultsStore.get(
            key: .defaultKernelBinaryPath
        )

        logger.info(
            "Starting kernel installation from: \(defaultKernelURL)"
        )
        logger.info(
            "Kernel binary path in archive: \(defaultKernelBinaryPath)"
        )

        guard let sourceURL = URL(string: defaultKernelURL) else {
            throw ContainerizationError(
                .invalidArgument,
                message: "Invalid kernel URL: \(defaultKernelURL)"
            )
        }

        // Create temp directory for download and extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Download the kernel tar file
        let tarFile = tempDir.appendingPathComponent(
            sourceURL.lastPathComponent
        )

        logger.info("Downloading from: \(sourceURL) to: \(tarFile.path)")

        progress.step("Downloading kernel")
        let response = try await FileDownloader(
            destination: tarFile,
            progress: progress
        ).download(from: sourceURL)

        if let httpResponse = response as? HTTPURLResponse {
            logger.info(
                "Download response status: \(httpResponse.statusCode)"
            )
            guard httpResponse.statusCode == 200 else {
                throw ContainerizationError(
                    .internalError,
                    message:
                        "Failed to download kernel: HTTP \(httpResponse.statusCode)"
                )
            }
        }

        logger.info("Downloaded to: \(tarFile.path)")

        // Unpacking happens on the kernel service's actor, off the main thread
        progress.step("Unpacking kernel")
        let service = try await getKernelService()
        try await service.installKernelFrom(
            tar: tarFile,
            kernelFilePath: defaultKernelBinaryPath,
            platform: .current,
            force: true
        )

        logger.info("Kernel installed successfully")
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
            logger.warning("Failed to check kernel: \(error)")

            return false
        }
    }
}
