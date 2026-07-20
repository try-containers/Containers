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
    }

    enum Step: Int, CaseIterable {
        case method = 0
        case configuration = 1

        var isCentered: Bool {
            switch self {
            case .method:
                true
            case .configuration:
                false
            }
        }
    }

    @Environment(ImageManager.self) private var imageManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var currentStep: Step = .method
    @SwiftUI.State private var stepTransitionDirection: Int = 1
    @SwiftUI.State private var selectedMethod: CreationMethod?
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var isCreating: Bool = false
    @SwiftUI.State private var creationTask: Task<Void, Never>?
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

    var body: some View {
        CreateView(
            title: "Create Image",
            errorMessage: $errorMessage,
            isProcessing: isCreating,
            progressTitle: progressMessage,
            width: 600,
            height: 480,
            showsHeader: false,
            contentAlignment: .center,
            contentID: currentStep,
            contentTransition: stepTransition,
            onCancel: {
                if isCreating {
                    cancelCreation()
                } else {
                    dismiss()
                }
            },
            content: {
                currentStepContent
                    .multilineTextAlignment(.leading)
            },
            actions: {
                if currentStep.rawValue > 0 && !isCreating {
                    Button(
                        action: previousStep,
                        label: {
                            Text("Back")
                                .padding(.horizontal, 2)
                        }
                    )
                    .buttonStyle(.bordered)
                }

                if !isCreating {
                    switch currentStep {
                    case .method:
                        Button(
                            action: nextStep,
                            label: {
                                Text("Next")
                                    .padding(.horizontal, 2)
                            }
                        )
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!canProceedToNextStep)
                    case .configuration:
                        Button(
                            action: createImage,
                            label: {
                                Text("Create")
                                    .padding(.horizontal, 2)
                            }
                        )
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!canProceedToNextStep)
                    }
                }
            }
        )
        .animation(.default, value: isCreating)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .method:
            CreateImageMethodStep(
                selectedMethod: $selectedMethod,
                onSelection: selectCreationMethod
            )
        case .configuration:
            CreateImageConfigurationStep(
                selectedMethod: selectedMethod,
                defaultFileDialogDirectory:
                    defaultFileDialogDirectory,
                tarContentTypes: tarContentTypes,
                shouldLoadPullFeaturedImages: shouldLoadPullFeaturedImages,
                onFileSelection: { errorMessage = nil },
                errorMessage: $errorMessage,
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
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: stepTransitionDirection > 0 ? .trailing : .leading),
            removal: .move(edge: stepTransitionDirection > 0 ? .leading : .trailing)
        )
    }

    private var progressMessage: String {
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
        case .configuration:
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
        errorMessage = nil

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
        withAnimation(.default) {
            currentStep = nextStep
            errorMessage = nil
        } completion: {
            completeStepTransition()
        }
    }

    func previousStep() {
        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else {
            return
        }
        prepareStepTransition()
        stepTransitionDirection = -1
        withAnimation(.default) {
            currentStep = previousStep
            errorMessage = nil
        } completion: {
            completeStepTransition()
        }
    }

    // MARK: - Image Creation

    func createImage() {
        guard let method = selectedMethod else { return }

        creationTask = Task { @MainActor in
            isCreating = true
            errorMessage = nil

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

            } catch {
                isCreating = false
                errorMessage = "\(error)"
            }
        }
    }

    func cancelCreation() {
        creationTask?.cancel()
        creationTask = nil
        isCreating = false
        errorMessage = "Operation cancelled"
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
