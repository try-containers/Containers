//
//  ResolvedMounts.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import Foundation

/// The mounts a container is created with, resolved from what the create
/// sheet drafted. Volumes that do not exist yet are created along the way.
struct ResolvedMounts {
    /// The mounts in the order the guest takes them: what the host binds in,
    /// then the temporary filesystems, then the volumes. A volume nested under
    /// a bind mount has to follow it, or the bind covers it over.
    private(set) var mounts: [Filesystem] = []

    @MainActor
    init(
        mounts: [Mount],
        volumes: [VolumeMount],
        using volumeManager: VolumeManager
    ) async throws {
        var bindMounts: [Filesystem] = []
        var temporaryFileSystems: [Filesystem] = []
        var resolvedVolumes: [Filesystem] = []

        var takenTargets = Set<String>()
        let options: [String] = []
        let existingVolumes = try await volumeManager.list()

        func reserve(_ target: String) throws {
            guard takenTargets.insert(target).inserted else {
                throw MountError.duplicateTarget(target)
            }
        }

        for mount in mounts {
            let target = mount.trimmedTarget

            // A row added and then left alone is not a mount.
            guard mount.isTemporary || mount.hostURL != nil || !target.isEmpty
            else {
                continue
            }

            guard !target.isEmpty else {
                throw MountError.targetMissing
            }
            guard target.hasPrefix("/") else {
                throw MountError.targetNotAbsolute
            }
            try reserve(target)

            guard !mount.isTemporary else {
                temporaryFileSystems.append(
                    .tmpfs(destination: target, options: options)
                )
                continue
            }

            guard let source = mount.hostURL, source.path.hasPrefix("/") else {
                throw MountError.sourceNotAbsolute
            }

            bindMounts.append(
                .virtiofs(
                    source: source.path,
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

            resolvedVolumes.append(
                .volume(
                    name: volume.name,
                    format: volume.format,
                    source: volume.source,
                    destination: target,
                    options: options
                )
            )
        }

        self.mounts = bindMounts + temporaryFileSystems + resolvedVolumes
    }
}
