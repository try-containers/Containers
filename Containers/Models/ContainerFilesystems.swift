//
//  ContainerFilesystems.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import Foundation

/// The filesystems a container is created with, resolved from what the create
/// sheet drafted. Volumes that do not exist yet are created along the way.
struct ContainerFilesystems {
    var bindMounts: [Filesystem] = []
    var temporaryFileSystems: [Filesystem] = []
    var volumes: [Filesystem] = []

    init() {}

    @MainActor
    init(
        mounts: [Mount],
        volumes: [VolumeMount],
        using volumeManager: VolumeManager
    ) async throws {
        var takenTargets = Set<String>()
        let options: [String] = []
        let existingVolumes = try await volumeManager.list()

        func reserve(_ target: String) throws {
            guard takenTargets.insert(target).inserted else {
                throw MountError.duplicateTarget(target)
            }
        }

        for mount in mounts {
            let source = mount.trimmedSource
            let target = mount.trimmedTarget

            // A row added and then left alone is not a mount.
            guard !source.isEmpty || !target.isEmpty else { continue }

            guard !target.isEmpty else {
                throw MountError.targetMissing
            }
            guard target.hasPrefix("/") else {
                throw MountError.targetNotAbsolute
            }
            try reserve(target)

            guard !source.isEmpty else {
                temporaryFileSystems.append(
                    .tmpfs(destination: target, options: options)
                )
                continue
            }

            let resolvedSource = (source as NSString).expandingTildeInPath
            guard resolvedSource.hasPrefix("/") else {
                throw MountError.sourceNotAbsolute
            }

            bindMounts.append(
                .virtiofs(
                    source: resolvedSource,
                    destination: target,
                    options: options
                )
            )
        }

        for draft in volumes {
            let target = draft.trimmedTarget

            guard !draft.trimmedVolumeName.isEmpty || !target.isEmpty else {
                continue
            }

            guard target.hasPrefix("/") else {
                throw MountError.targetNotAbsolute
            }
            try reserve(target)

            let volume = try await volumeManager.volume(
                named: draft.source == .anonymousVolume
                    ? "" : draft.trimmedVolumeName,
                among: existingVolumes
            )

            self.volumes.append(
                .volume(
                    name: volume.name,
                    format: volume.format,
                    source: volume.source,
                    destination: target,
                    options: options
                )
            )
        }
    }
}
