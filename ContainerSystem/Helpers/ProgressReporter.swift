//
//  ProgressReporter.swift
//  Containers
//
//  What a long operation is doing, in the terms the container CLI reports it.
//

import ContainerizationExtras
import Foundation
import Observation

/// The running state behind the message a sheet shows while the app pulls,
/// builds, loads or unpacks.
///
/// The library only ever says how much it has done — the four counter events —
/// so the name of the step is set here, around each call, the way the CLI sets
/// it around the same ones. A step keeps its own counts: starting the next one
/// clears them and takes the numbering on.
@Observable
@MainActor
public final class ProgressReporter {
    /// The step being performed, e.g. "Fetching image".
    public private(set) var description: String = ""

    /// What the step has done so far, e.g. "3 of 12 blobs, 42 MB of 310 MB".
    public private(set) var detail: String = ""

    private var itemsName: String = ""
    private var task: Int = 0
    private var totalTasks: Int = 0
    private var items: Int = 0
    private var totalItems: Int = 0
    private var size: Int64 = 0
    private var totalSize: Int64 = 0

    public init() {}

    /// Starts an operation of `totalTasks` steps, leaving nothing of the last.
    public func begin(totalTasks: Int) {
        description = ""
        detail = ""
        itemsName = ""
        task = 0
        self.totalTasks = totalTasks
        resetStep()
    }

    /// Moves on to the next step, which counts from zero again.
    public func step(_ description: String, itemsName: String = "") {
        resetStep()

        self.description = description
        self.itemsName = itemsName
        self.task += 1
        // A step the caller could not know about, such as starting a builder
        // that was not running, takes the count up with it.
        self.totalTasks = max(totalTasks, task)
        self.detail = format()
    }

    /// Reports a line a tool printed for itself, such as BuildKit's own steps.
    public func report(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        detail = trimmed.components(separatedBy: .newlines).last ?? trimmed
    }

    public func update(_ events: [ProgressEvent]) {
        for event in events {
            switch event {
            case .addItems(let value):
                items += value
            case .addTotalItems(let value):
                totalItems += value
            case .addSize(let value):
                size += value
            case .addTotalSize(let value):
                totalSize += value
            }
        }

        detail = format()
    }

    public func finish() {
        begin(totalTasks: 0)
    }

    /// A handler for the services, which report from off the main actor. The
    /// hop is awaited so that batches land in the order they were sent.
    public nonisolated func handler() -> ProgressHandler {
        { [weak self] events in
            await MainActor.run {
                self?.update(events)
            }
        }
    }

    private func resetStep() {
        items = 0
        totalItems = 0
        size = 0
        totalSize = 0
    }

    /// The CLI's line, minus what only a terminal can draw: the step count,
    /// the percentage, the items and the size it has moved.
    private func format() -> String {
        // Nothing is drawn until the step knows what it is counting: a line
        // that arrives a piece at a time reads as a flicker.
        guard totalItems > 0 || totalSize > 0 else { return "" }

        var components: [String] = []

        if totalTasks > 0, task > 0 {
            components.append("Step \(task) of \(totalTasks)")
        }

        if let percent {
            components.append("\(percent)%")
        }

        if items > 0 {
            let name = itemsName.isEmpty ? "items" : itemsName

            components.append(
                totalItems > 0
                    ? "\(items) of \(totalItems) \(name)" : "\(items) \(name)"
            )
        }

        if size > 0 {
            components.append(
                totalSize > 0
                    ? Self.formatted(size, of: totalSize)
                    : Self.formatted(size)
            )
        }

        return components.joined(separator: " · ")
    }

    /// Size leads, as it does in the CLI, with the items only standing in for
    /// a step that never says how big it is.
    private var percent: Int? {
        if totalSize > 0 {
            return min(Int(size * 100 / totalSize), 100)
        }

        if totalItems > 0 {
            return min(items * 100 / totalItems, 100)
        }

        return nil
    }

    private static func formatted(
        _ bytes: Int64,
        units: ByteCountFormatter.Units = []
    ) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = units
        // A size keeps its decimal place and its digits whatever it reads, so
        // the line does not change width as the count climbs.
        formatter.zeroPadsFractionDigits = true
        formatter.allowsNonnumericFormatting = false

        return formatter.string(fromByteCount: bytes)
    }

    /// Two sizes are drawn in the unit of the larger, which is named once, as
    /// the CLI's line does: neither the unit nor the width changes underneath
    /// what is being read.
    private static func formatted(_ size: Int64, of total: Int64) -> String {
        let units = units(for: total)
        let sizeText = formatted(size, units: units)
        let totalText = formatted(total, units: units)
        let sizeParts = sizeText.split(separator: " ", maxSplits: 1)
        let totalParts = totalText.split(separator: " ", maxSplits: 1)

        guard sizeParts.count == 2, totalParts.count == 2,
            sizeParts[1] == totalParts[1]
        else {
            return "\(sizeText) of \(totalText)"
        }

        return "\(sizeParts[0]) of \(totalParts[0]) \(totalParts[1])"
    }

    private static func units(for total: Int64) -> ByteCountFormatter.Units {
        let kib: Int64 = 1024

        switch total {
        case (kib * kib * kib * kib)...:
            return .useTB
        case (kib * kib * kib)...:
            return .useGB
        case (kib * kib)...:
            return .useMB
        default:
            return .useKB
        }
    }
}
