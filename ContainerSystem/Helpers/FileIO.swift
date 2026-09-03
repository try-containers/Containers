//
//  FileIO.swift
//  Containers
//
//  Blocking filesystem and archive work.
//
//  Created by Axel Martinez on 2026/09/02.
//

import ContainerizationArchive
import Foundation

/// Copies, moves and archive (un)packing, performed on this actor's executor.
///
/// The managers are `@MainActor` so their observable state can be read straight
/// from SwiftUI. Copying a build context or unpacking an image tar there would
/// block the window for as long as the copy takes, so that work is awaited here
/// instead. Actor isolation is what guarantees it leaves the main thread:
/// a `nonisolated` helper would run inline on the caller again the day
/// `SWIFT_APPROACHABLE_CONCURRENCY` is turned on for this target.
actor FileIO {
    static let shared = FileIO()

    func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func contents(of file: URL) throws -> Data {
        try Data(contentsOf: file)
    }

    /// Extracts `archive` into `directory`, returning the members it rejected.
    @discardableResult
    func extractArchive(at archive: URL, to directory: URL) throws -> [String] {
        let reader = try ArchiveReader(file: archive)

        return try reader.extractContents(to: directory)
    }

    func writeArchive(directory: URL, to destination: URL) throws {
        let writer = try ArchiveWriter(
            format: .pax,
            filter: .none,
            file: destination
        )

        try writer.archiveDirectory(directory)
        try writer.finishEncoding()
    }
}
