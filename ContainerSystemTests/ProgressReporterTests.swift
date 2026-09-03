//
//  ProgressReporterTests.swift
//  ContainerSystemTests
//
//  The line a sheet shows while a long operation runs.
//

import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Progress reporter")
@MainActor
struct ProgressReporterTests {

    @Test("Nothing is detailed until the step knows what it is counting")
    func staysQuietWithoutTotals() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 2)
        progress.step("Fetching image", itemsName: "blobs")

        #expect(progress.detail == "")

        // A count with no total behind it still reads as a flicker.
        progress.update([.addItems(1)])

        #expect(progress.detail == "")

        progress.update([.addTotalItems(4)])

        #expect(progress.detail.contains("1 of 4 blobs"))
    }

    @Test("A step reports its number against the total")
    func reportsStepNumber() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 3)
        progress.step("Fetching image", itemsName: "blobs")
        progress.update([.addTotalItems(2), .addItems(1)])

        #expect(progress.detail.contains("Step 1 of 3"))
    }

    @Test("Starting the next step clears the last one's counts")
    func stepClearsCounts() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 2)
        progress.step("Fetching image", itemsName: "blobs")
        progress.update([.addTotalItems(4), .addItems(4)])

        #expect(progress.detail.contains("4 of 4 blobs"))

        progress.step("Unpacking image", itemsName: "entries")

        #expect(progress.description == "Unpacking image")
        #expect(progress.detail == "")
    }

    @Test("A step nobody counted on takes the total up with it")
    func unannouncedStepRaisesTotal() {
        let progress = ProgressReporter()

        // Two steps were expected; starting a builder makes it three.
        progress.begin(totalTasks: 2)
        progress.step("Fetching image")
        progress.step("Dialing builder")
        progress.step("Building image", itemsName: "layers")
        progress.update([.addTotalItems(1), .addItems(1)])

        #expect(progress.detail.contains("Step 3 of 3"))
    }

    @Test("Percentage is capped at 100 when more arrives than was promised")
    func percentIsCapped() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 1)
        progress.step("Fetching image")
        progress.update([.addTotalSize(100), .addSize(250)])

        #expect(progress.detail.contains("100%"))
    }

    @Test("Size decides the percentage when items are counted too")
    func sizeLeadsThePercentage() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 1)
        progress.step("Fetching image", itemsName: "blobs")

        // Items alone would read 100%; the size is only a quarter done.
        progress.update([
            .addTotalItems(4), .addItems(4),
            .addTotalSize(1000), .addSize(250),
        ])

        #expect(progress.detail.contains("25%"))
        #expect(!progress.detail.contains("100%"))
    }

    @Test("Two sizes are drawn in one unit, named once")
    func sizesShareOneUnit() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 1)
        progress.step("Fetching image")

        let mib: Int64 = 1024 * 1024
        progress.update([.addTotalSize(10 * mib), .addSize(3 * mib)])

        let detail = progress.detail
        let unitMentions = detail.components(separatedBy: "MB").count - 1

        #expect(detail.contains(" of "))
        #expect(
            unitMentions == 1,
            "expected the unit named once, got \(detail)"
        )
    }

    @Test("A tool's own output becomes the detail, one line at a time")
    func reportKeepsTheLastLine() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 1)
        progress.step("Building image")
        progress.report("#4 resolve image\n#5 exporting layers")

        #expect(progress.detail == "#5 exporting layers")

        // Blank output leaves what was there rather than clearing it.
        progress.report("   \n  ")

        #expect(progress.detail == "#5 exporting layers")
    }

    @Test("Finishing leaves nothing of the operation behind")
    func finishClearsEverything() {
        let progress = ProgressReporter()

        progress.begin(totalTasks: 1)
        progress.step("Fetching image", itemsName: "blobs")
        progress.update([.addTotalItems(2), .addItems(1)])
        progress.finish()

        #expect(progress.description == "")
        #expect(progress.detail == "")
    }
}
