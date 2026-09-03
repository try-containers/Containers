//
//  CreateImageWizard.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import ContainerSystem
import ContainerizationOCI
import ContainerizationOS
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CreateImageView: View {
    let tarContentTypes = [UTType(filenameExtension: "tar")].compactMap { $0 }

    enum CreationMethod: String, CaseIterable {
        case pull = "Pull from Registry"
        case build = "Build from Dockerfile"
        case load = "Load from Tar"

        var icon: String {
            switch self {
            case .pull: return "arrow.down.circle.fill"
            case .build: return "hammer.fill"
            case .load: return "folder.fill"
            }
        }

        var description: String {
            switch self {
            case .pull: return "Download an image from a remote registry"
            case .build: return "Build an image from a Dockerfile"
            case .load: return "Load an image from a tar archive"
            }
        }

        /// The steps the method reports, which the progress counts against.
        var totalSteps: Int {
            switch self {
            case .pull: return 2
            case .build: return 3
            case .load: return 2
            }
        }
    }

    /// Where the sheet goes once the user says yes to stopping the work.
    private enum StopIntent {
        case goBack
        case close
    }

    enum Step: Int, CaseIterable {
        case method = 0
        case configuration = 1
        /// The work itself, so that leaving it is an ordinary step back.
        case progress = 2

        var isCentered: Bool {
            switch self {
            case .method:
                true
            case .configuration:
                false
            case .progress:
                true
            }
        }
    }

    @Environment(ImageManager.self) private var imageManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var currentStep: Step = .method
    @SwiftUI.State private var stepTransitionDirection: Int = 1
    @SwiftUI.State private var selectedMethod: CreationMethod?
    @SwiftUI.State private var failure: ErrorAlert?
    @SwiftUI.State private var creationTask: Task<Void, Never>?
    @SwiftUI.State private var stopIntent: StopIntent?
    @SwiftUI.State private var tarFile: URL?
    @SwiftUI.State private var forceLoad: Bool = false
    @SwiftUI.State private var contextDirectory: URL?
    @SwiftUI.State private var imageName: String = ""
    @SwiftUI.State private var tag: String = "latest"
    @SwiftUI.State private var pullPlatform: PlatformSelection = .any
    @SwiftUI.State private var dockerFile: URL?
    @SwiftUI.State private var buildTag: String = ""
    @SwiftUI.State private var buildPlatform: PlatformSelection = .platform(.current)
    @SwiftUI.State private var buildArguments: [KeyValue] = []
    @SwiftUI.State private var targetStage: String = ""
    @SwiftUI.State private var shouldLoadPullFeaturedImages: Bool = false
    @SwiftUI.State private var paneTitle: String?

    var body: some View {
        CreateView(
            title: "Create Image",
            isProcessing: isCreating,
            isFailed: failure != nil,
            progressTitle: progressMessage,
            width: Self.sheetWidth,
            height: 480,
            showsHeader: false,
            contentAlignment: .center,
            showsFooterDivider: false,
            contentID: AnyHashable(currentStep),
            contentTransition: stepTransition,
            contentTitle: paneTitle,
            // Only the suggestions are ruled off into their own section.
            contentTitleRule: selectedMethod == .pull,
            content: {
                currentStepContent
                    .multilineTextAlignment(.leading)
            },
            actions: {
                Button {
                    confirmStop(.close)
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(
                    action: { confirmStop(.goBack) },
                    label: {
                        Text("Previous")
                            .frame(width: .sheetButtonLabelWidth)
                    }
                )
                .buttonStyle(.bordered)
                .disabled(currentStep.rawValue == 0 && failure == nil)

                switch currentStep {
                case .method:
                    Button(
                        action: nextStep,
                        label: {
                            Text("Next")
                                .frame(width: .sheetButtonLabelWidth)
                        }
                    )
                    .defaultAction(enabled: canProceedToNextStep)
                case .configuration, .progress:
                    Button(
                        action: createImage,
                        label: {
                            Text("Create")
                                .frame(width: .sheetButtonLabelWidth)
                        }
                    )
                    .defaultAction(
                        enabled: !isCreating && canProceedToNextStep
                            && failure == nil
                    )
                }
            },
            progress: {
                if !imageManager.progress.detail.isEmpty {
                    Text(imageManager.progress.detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            },
            failure: {
                if let failure {
                    CreateImageFailure(failure: failure)
                }
            }
        )
        .confirmationDialog(
            "Stop Creating Image",
            isPresented: Binding(
                get: { stopIntent != nil },
                set: { presented in
                    if !presented { stopIntent = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: stopIntent
        ) { intent in
            Button("Stop", role: .destructive) {
                stop(intent)
            }

            Button("Continue", role: .cancel) {}
        } message: { _ in
            Text(
                "The image hasn’t finished being created. Stopping now discards it."
            )
        }
    }

    /// Work under way is only stopped on purpose, so the button asks first.
    private func confirmStop(_ intent: StopIntent) {
        guard isCreating else {
            stop(intent)
            return
        }

        stopIntent = intent
    }

    private func stop(_ intent: StopIntent) {
        switch intent {
        case .goBack:
            previousStep()
        case .close:
            cancelCreation()
            dismiss()
        }
    }

    /// The work is a step, so nothing else has to be asked whether it runs.
    private var isCreating: Bool {
        currentStep == .progress
    }

    private func paneTitle(for step: Step) -> String? {
        guard step == .configuration,
            selectedMethod == .build || selectedMethod == .pull
        else {
            return nil
        }

        return "Choose options for your new image"
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .method:
            CreateImageMethod(
                selectedMethod: $selectedMethod,
                onSelection: selectCreationMethod
            )
        case .configuration:
            CreateImageConfiguration(
                selectedMethod: selectedMethod,
                defaultFileDialogDirectory:
                    defaultFileDialogDirectory,
                tarContentTypes: tarContentTypes,
                shouldLoadPullFeaturedImages: shouldLoadPullFeaturedImages,
                onFileSelection: { failure = nil },
                error: $failure,
                imageName: $imageName,
                tag: $tag,
                pullPlatform: $pullPlatform,
                contextDirectory: $contextDirectory,
                dockerFile: $dockerFile,
                buildTag: $buildTag,
                buildPlatform: $buildPlatform,
                buildArguments: $buildArguments,
                targetStage: $targetStage,
                tarFile: $tarFile,
                forceLoad: $forceLoad
            )
        case .progress:
            EmptyView()
        }
    }

    private static let sheetWidth: CGFloat = 600
    private static let stepAnimation: Animation = .easeOut(duration: 0.2)

    private var stepTransition: AnyTransition {
        let distance = Self.sheetWidth / 3
        let shift = stepTransitionDirection > 0 ? distance : -distance

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: shift)),
            removal: .identity
        )
    }

    private var progressMessage: String {
        let step = imageManager.progress.description

        guard step.isEmpty else { return step }
        guard let method = selectedMethod else { return "Processing..." }

        switch method {
        case .pull:
            return "Pulling image from registry..."
        case .build:
            return
                "Building image from Dockerfile...\nThis may take several minutes."
        case .load:
            return "Loading image from tar archive..."
        }
    }

    // MARK: - Navigation

    private var defaultFileDialogDirectory: URL? {
        try? FileManager.default.url(
            for: .desktopDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    var canProceedToNextStep: Bool {
        switch currentStep {
        case .method:
            return selectedMethod != nil
        case .configuration, .progress:
            switch selectedMethod {
            case .pull:
                return !imageName.isEmpty
            case .build:
                return contextDirectory != nil && dockerFile != nil
            case .load:
                return tarFile != nil
            case .none:
                return false
            }
        }
    }

    private func selectCreationMethod(_ method: CreationMethod) {
        selectedMethod = method
    }

    private func selectTarArchiveAndLoad() {
        failure = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = tarFile?.parent ?? defaultFileDialogDirectory
        panel.allowedContentTypes = tarContentTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        tarFile = url
        createImage()
    }

    private func prepareStepTransition() {
        shouldLoadPullFeaturedImages = false
    }

    private func completeStepTransition() {
        shouldLoadPullFeaturedImages = currentStep == .configuration && selectedMethod == .pull
    }

    func nextStep() {
        if selectedMethod == .load {
            selectTarArchiveAndLoad()
            return
        }

        guard let nextStep = Step(rawValue: currentStep.rawValue + 1) else {
            return
        }

        prepareStepTransition()
        stepTransitionDirection = 1
        paneTitle = paneTitle(for: nextStep)
        withAnimation(Self.stepAnimation) {
            currentStep = nextStep
            failure = nil
        } completion: {
            completeStepTransition()
        }
    }

    func previousStep() {
        cancelCreation()

        // The failure stands in front of the step that produced it, so going
        // back leaves the failure rather than the step.
        guard failure == nil else {
            stepTransitionDirection = -1
            paneTitle = paneTitle(for: currentStep)
            withAnimation(Self.stepAnimation) {
                failure = nil
            }
            return
        }

        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        prepareStepTransition()
        stepTransitionDirection = -1
        paneTitle = paneTitle(for: previousStep)
        withAnimation(Self.stepAnimation) {
            currentStep = previousStep
            failure = nil
        } completion: {
            completeStepTransition()
        }
    }

    // MARK: - Image Creation

    func createImage() {
        guard let method = selectedMethod else { return }

        prepareStepTransition()
        stepTransitionDirection = 1
        paneTitle = nil

        withAnimation(Self.stepAnimation) {
            currentStep = .progress
            failure = nil
        }

        creationTask = Task { @MainActor in
            imageManager.progress.begin(totalTasks: method.totalSteps)

            defer {
                imageManager.progress.finish()
            }

            do {
                switch method {
                case .pull:
                    try await pullImage()
                case .build:
                    try await buildImage()
                case .load:
                    try await loadImage()
                }

                // Dismiss on success
                dismiss()

            } catch is CancellationError {
                // Going back is what called this off, and it has moved on.
            } catch {
                // Failing is not a step being turned to: the message takes the
                // place the progress held, without the assistant's slide.
                stepTransitionDirection = -1
                currentStep = .configuration
                failure = ErrorAlert(
                    failureTitle(for: method),
                    error: error,
                    // What went wrong here reads in full, so there is
                    // nothing to keep folded away.
                    showsDetails: false
                )
            }
        }
    }

    /// Stops work still in flight. Where the sheet goes next is the caller's
    /// to say: back a step, or away altogether.
    func cancelCreation() {
        creationTask?.cancel()
        creationTask = nil
    }

    private func failureTitle(for method: CreationMethod) -> String {
        switch method {
        case .pull:
            "The image couldn’t be pulled."
        case .build:
            "The image couldn’t be built."
        case .load:
            "The image couldn’t be loaded."
        }
    }

    func pullImage() async throws {
        let reference = tag.isEmpty ? imageName : "\(imageName):\(tag)"

        try await imageManager.pull(
            reference: reference,
            platform: pullPlatform.platform
        )
    }

    func buildImage() async throws {
        guard let contextDirectory, let dockerFile else {
            throw NSError(
                domain: "BuildError",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Missing context directory or Dockerfile"
                ]
            )
        }

        let validBuildArguments = self.buildArguments.filter({
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })

        try await imageManager.build(
            dockerFile: dockerFile,
            contextDirectory: contextDirectory,
            tag: buildTag,
            cpus: 2,
            memory: 1024.mib(),
            vSockPort: 8088,
            outputs: [
                BuildImageOutputConfiguration(type: .oci, additionalFields: [])
            ],
            platforms: [buildPlatform.platform ?? Platform.current],
            buildArguments: validBuildArguments,
            labels: [],
            noCache: false,
            targetStage: targetStage,
            cacheIn: [],
            cacheOut: []
        )
    }

    func loadImage() async throws {
        guard let tarFile else {
            throw NSError(
                domain: "LoadError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No tar file selected"]
            )
        }

        try await imageManager.load(tar: tarFile, force: forceLoad)
    }
}
