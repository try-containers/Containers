//
//  ContainerMountPlanner.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import Containerization
import Foundation

struct ContainerMounts {
    var bindMounts: [Filesystem] = []
    var temporaryFileSystems: [Filesystem] = []
    var volumes: [Filesystem] = []
}

enum ContainerMountError: LocalizedError {
    case targetMissing
    case targetNotAbsolute
    case sourceNotAbsolute
    case duplicateTarget(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing:
            "Mounts require a target."
        case .targetNotAbsolute:
            "Mount target must be absolute."
        case .sourceNotAbsolute:
            "Mount source must be an absolute host path."
        case .duplicateTarget(let target):
            "A mount already exists at \(target)."
        }
    }
}

@MainActor
enum ContainerMountPlanner {

    static func plan(
        mounts: [MountConfiguration],
        volumes: [VolumeMountConfiguration],
        volumeManager: VolumeManager
    ) async throws -> ContainerMounts {
        var planned = ContainerMounts()
        var takenTargets = Set<String>()
        let options: [String] = []
        let existingVolumes = try await volumeManager.list()

        func reserve(_ target: String) throws {
            guard takenTargets.insert(target).inserted else {
                throw ContainerMountError.duplicateTarget(target)
            }
        }

        for mount in mounts {
            let source = mount.trimmedSource
            let target = mount.trimmedTarget

            // A row added and then left alone is not a mount.
            guard !source.isEmpty || !target.isEmpty else { continue }

            guard !target.isEmpty else {
                throw ContainerMountError.targetMissing
            }
            guard target.hasPrefix("/") else {
                throw ContainerMountError.targetNotAbsolute
            }
            try reserve(target)

            guard !source.isEmpty else {
                planned.temporaryFileSystems.append(
                    .tmpfs(destination: target, options: options)
                )
                continue
            }

            let resolvedSource = (source as NSString).expandingTildeInPath
            guard resolvedSource.hasPrefix("/") else {
                throw ContainerMountError.sourceNotAbsolute
            }

            planned.bindMounts.append(
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
                throw ContainerMountError.targetNotAbsolute
            }
            try reserve(target)

            let volume = try await volume(
                named: draft.source == .anonymousVolume
                    ? "" : draft.trimmedVolumeName,
                among: existingVolumes,
                using: volumeManager
            )

            planned.volumes.append(
                .volume(
                    name: volume.name,
                    format: volume.format,
                    source: volume.source,
                    destination: target,
                    options: options
                )
            )
        }

        return planned
    }

    /// An unnamed draft gets a fresh anonymous volume; a named one reuses the
    /// existing volume when there is one.
    static func volume(
        named name: String,
        among existing: [Volume],
        using volumeManager: VolumeManager
    ) async throws -> Volume {
        if !name.isEmpty, let match = existing.first(where: { $0.name == name }) {
            return match
        }

        var volumeName = name
        var labels: [KeyValue] = []

        if volumeName.isEmpty {
            volumeName = VolumeStorage.generateAnonymousVolumeName()
            labels.append(.init(key: Volume.anonymousLabel))
        }

        return try await volumeManager.create(
            name: volumeName,
            labels: labels,
            options: [],
            sizeInBytes: nil
        )
    }
}
