//
//  ProgressStepsTests.swift
//  ContainerSystemTests
//
//  How an operation counts its steps into a Progress.
//

import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerSystem

@Suite("Progress steps")
@MainActor
struct ProgressStepsTests {

    @Test("A step shows its description on the progress it belongs to")
    func showsStepDescription() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { _ in
            #expect(progress.localizedDescription == "Fetching image")
        }

        try await progress.performStep("Unpacking image") { _ in
            #expect(progress.localizedDescription == "Unpacking image")
        }
    }

    @Test("The deepest step under way speaks for the whole operation")
    func deepestStepWins() async throws {
        let progress = Progress(totalUnitCount: 1)

        try await progress.performStep("Starting builder") { builder in
            builder.totalUnitCount = 1

            try await builder.performStep("Fetching builder image") { step in
                await step.updateHandler()([.addTotalItems(4), .addItems(1)])

                #expect(progress.localizedDescription == "Fetching builder image")
                #expect(progress.localizedAdditionalDescription == "1 of 4")
            }
        }
    }

    @Test("Each step counts for its share of the operation")
    func stepsShareTheOperation() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { step in
            await step.updateHandler()([.addTotalItems(4), .addItems(2)])

            #expect(progress.fractionCompleted == 0.25)
        }

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("A step that reports no amounts still counts once it is done")
    func unmeasuredStepCompletes() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Creating container") { step in
            #expect(step.isIndeterminate)
        }

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("A step that fails leaves the operation where it was")
    func failedStepDoesNotComplete() async {
        struct Failure: Error {}

        let progress = Progress(totalUnitCount: 2)

        await #expect(throws: Failure.self) {
            try await progress.performStep("Fetching image") { _ in
                throw Failure()
            }
        }

        #expect(progress.fractionCompleted == 0)
    }

    @Test("A step that has finished no longer speaks for the operation")
    func finishedStepStopsMirroring() async throws {
        let progress = Progress(totalUnitCount: 2)
        var finished: Progress?

        try await progress.performStep("Fetching image") { step in
            finished = step
        }

        finished?.localizedDescription = "Stale"

        #expect(progress.localizedDescription == "Fetching image")
        // Completing an unmeasured step does not say "1 of 1" here.
        #expect(progress.localizedAdditionalDescription == "")
    }

    @Test("Reports that arrive once a step is complete are dropped")
    func lateReportsAreDropped() async throws {
        let progress = Progress(totalUnitCount: 2)
        var update: ProgressHandler?

        try await progress.performStep("Fetching image") { step in
            update = step.updateHandler()
            await update?([.addTotalItems(4), .addItems(4)])
        }

        #expect(progress.fractionCompleted == 0.5)

        await update?([.addTotalItems(4), .addItems(1)])

        #expect(progress.fractionCompleted == 0.5)
        #expect(progress.completedUnitCount == 1)
    }

    @Test("Bytes measure the step where the service says how many there are")
    func bytesOverItems() async {
        let progress = Progress(totalUnitCount: 0)
        let update = progress.updateHandler()

        await update([.addTotalItems(10), .addItems(5)])

        #expect(progress.fractionCompleted == 0.5)

        await update([.addTotalSize(1000), .addSize(100)])

        #expect(progress.kind == .file)
        #expect(progress.totalUnitCount == 1000)
        #expect(progress.fractionCompleted == 0.1)
    }

    @Test("Counts without a total leave the step indeterminate")
    func countsWithoutTotal() async {
        let progress = Progress(totalUnitCount: 0)

        await progress.updateHandler()([.addItems(3)])

        #expect(progress.isIndeterminate)
    }

    @Test("One handler keeps one count across the work it is handed to")
    func handlerAccumulates() async {
        let progress = Progress(totalUnitCount: 0)
        let update = progress.updateHandler()

        await update([.addTotalItems(4), .addItems(1)])
        await update([.addItems(1)])

        #expect(progress.totalUnitCount == 4)
        #expect(progress.completedUnitCount == 2)
    }

    @Test("More arriving than was promised never takes the operation past its end")
    func overshootIsCapped() async throws {
        let progress = Progress(totalUnitCount: 1)

        try await progress.performStep("Fetching image") { step in
            await step.updateHandler()([.addTotalItems(2), .addItems(5)])

            #expect(progress.fractionCompleted < 1)
        }

        #expect(progress.fractionCompleted == 1)
    }

    @Test("A step that catches up with its total and is given more counts once")
    func totalGrowingAfterCatchingUp() async throws {
        let progress = Progress(totalUnitCount: 2)

        try await progress.performStep("Fetching image") { step in
            let update = step.updateHandler()

            await update([.addTotalItems(2), .addItems(2)])
            await update([.addTotalItems(2), .addItems(2)])
        }

        #expect(progress.fractionCompleted == 0.5)

        try await progress.performStep("Unpacking image") { _ in
            #expect(progress.fractionCompleted == 0.5)
        }

        #expect(progress.fractionCompleted == 1)
    }
}
