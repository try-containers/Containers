//
//  BuildImageView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import Foundation
import SwiftUI
import ContainerSystem
import ContainerizationOCI
import ContainerizationOS
import UniformTypeIdentifiers

struct BuildImageView: View {
    
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
        case review = 2
    }
    
    @Environment(ImageManager.self) private var imageManager
    @Environment(\.dismiss) private var dismiss
    
    @SwiftUI.State private var currentStep: Step = .method
    @SwiftUI.State private var selectedMethod: CreationMethod?
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var isCreating: Bool = false
    @SwiftUI.State private var creationTask: Task<Void, Never>?
    
    // Pull fields
    @SwiftUI.State private var imageName: String = ""
    @SwiftUI.State private var tag: String = "latest"
    @SwiftUI.State private var platformString: String = Platform.current.description
    
    // Build fields
    @SwiftUI.State private var dockerFile: URL?
    @SwiftUI.State private var contextDirectory: URL?
    @SwiftUI.State private var buildTag: String = ""
    @SwiftUI.State private var buildPlatformString: String = Platform.current.description
    @SwiftUI.State private var buildArguments: [KeyValue] = []
    @SwiftUI.State private var targetStage: String = ""
    
    // Load fields
    @SwiftUI.State private var tarFile: URL?
    
    var body: some View {
        VStack(spacing: 0) {
            if isCreating {
                // Centered loading view when creating
                creatingView()
            } else {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build Image")
                        .font(.headline)
                
                if let errorMessage = self.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isCreating {
                        creatingView()
                    } else {
                        Group {
                            switch currentStep {
                            case .method:
                                methodStep()
                            case .configuration:
                                configurationStep()
                            case .review:
                                reviewStep()
                            }
                        }
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.all, 24)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            
            Divider()
            
            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: {
                    self.dismiss()
                }, label: {
                    Text("Cancel")
                        .padding(.horizontal, 2)
                })
                .buttonStyle(.bordered)
                .disabled(isCreating)
                
                Spacer()
                
                if !isCreating && currentStep.rawValue > 0 {
                    Button(action: previousStep, label: {
                        Text("Back")
                            .padding(.horizontal, 2)
                    })
                    .buttonStyle(.bordered)
                }
                
                if !isCreating {
                    if currentStep != .review {
                        Button(action: nextStep, label: {
                            Text("Next")
                                .padding(.horizontal, 2)
                        })
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!canProceedToNextStep)
                    } else {
                        Button(action: createImage, label: {
                            Text("Create")
                                .padding(.horizontal, 2)
                        })
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding(.all, 24)
            }
        }
        .frame(width: 600, height: 520)
        .animation(.default, value: currentStep)
        .animation(.default, value: self.buildArguments.count)
        .animation(.default, value: isCreating)
        .interactiveDismissDisabled(isCreating)
    }
    
    // MARK: - Step Views
    
    @ViewBuilder
    func methodStep() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose how you want to create an image")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                ForEach(CreationMethod.allCases, id: \.self) { method in
                    Button(action: {
                        selectedMethod = method
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: method.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(selectedMethod == method ? .blue : .secondary)
                                .frame(width: 48)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(method.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(method.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedMethod == method {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 24))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMethod == method ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedMethod == method ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    func configurationStep() -> some View {
        Group {
            switch selectedMethod {
            case .pull:
                pullConfiguration()
            case .build:
                buildConfiguration()
            case .load:
                loadConfiguration()
            case .none:
                EmptyView()
            }
        }
    }
    
    @ViewBuilder
    func pullConfiguration() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            EditableField(
                title: "Image Name",
                subtitle: "Enter the image name from the registry",
                placeholder: "Ex: nginx, ubuntu, redis",
                value: $imageName
            )
            
            HStack {
                EditableField(
                    title: "Tag",
                    subtitle: "Specify the image tag or version",
                    placeholder: "Ex: latest, 1.0, stable",
                    value: $tag
                )
                
                Spacer()
                    .frame(width: 24)
                
                EditableField(
                    title: "Platform",
                    subtitle: "Target platform for the image",
                    placeholder: "Ex: linux/amd64",
                    value: $platformString
                )
            }
        }
    }
    
    @ViewBuilder
    func buildConfiguration() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dockerfile")
                    .font(.headline)
                Text("Select the Dockerfile to use")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FileSelection(fileURL: $dockerFile, errorMessage: $errorMessage, allowedContentTypes: [.item])
                    .onChange(of: dockerFile, {
                        guard let url = dockerFile else { return }
                        // Auto-set build directory to Dockerfile's parent if not already set
                        if contextDirectory == nil {
                            contextDirectory = url.parent
                        }
                    })
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Build Directory")
                    .font(.headline)
                Text("Root directory for the build context (defaults to Dockerfile's directory)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FileSelection(fileURL: $contextDirectory, errorMessage: $errorMessage, allowedContentTypes: [.directory])
                    .onChange(of: contextDirectory, {
                        guard let url = contextDirectory, dockerFile == nil else { return }
                        // Auto-suggest Dockerfile in the build directory
                        let dockerfileURL = url.appending(path: "Dockerfile")
                        if FileManager.default.fileExists(atPath: dockerfileURL.path) {
                            self.dockerFile = dockerfileURL
                        }
                    })
            }
            
            
            EditableField(
                title: "Image Tag",
                subtitle: "⭑ If empty, a generated UUID will be used",
                placeholder: "Ex: myapp:latest",
                value: $buildTag
            )
            
            EditableField(
                title: "Target Stage (Optional)",
                subtitle: "For multi-stage builds",
                placeholder: "Ex: production",
                value: $targetStage
            )
        }
    }
    
    @ViewBuilder
    func loadConfiguration() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tar Archive")
                    .font(.headline)
                Text("Select a tar archive containing the image")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                FileSelection(fileURL: $tarFile, errorMessage: $errorMessage, allowedContentTypes: [UTType(filenameExtension: "tar")].compactMap { $0 })
            }
        }
    }
    
    @ViewBuilder
    func reviewStep() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Review your configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                reviewItem(title: "Method", value: selectedMethod?.rawValue ?? "None")
                
                switch selectedMethod {
                case .pull:
                    reviewItem(title: "Image", value: "\(imageName):\(tag)")
                    reviewItem(title: "Platform", value: platformString)
                    
                case .build:
                    reviewItem(title: "Dockerfile", value: dockerFile?.path ?? "Not set")
                    reviewItem(title: "Build Directory", value: contextDirectory?.path ?? "Not set")
                    reviewItem(title: "Image Tag", value: buildTag.isEmpty ? "Auto-generated UUID" : buildTag)
                    if !targetStage.isEmpty {
                        reviewItem(title: "Target Stage", value: targetStage)
                    }
                    
                case .load:
                    reviewItem(title: "Tar File", value: tarFile?.lastPathComponent ?? "Not set")
                    
                case .none:
                    EmptyView()
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    func reviewItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    func creatingView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.5)

                VStack(spacing: 12) {
                    Text("Creating Image")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(progressMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: cancelCreation) {
                    Text("Cancel")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var progressMessage: String {
        guard let method = selectedMethod else { return "Processing..." }
        
        switch method {
        case .pull:
            return "Pulling image from registry..."
        case .build:
            return "Building image from Dockerfile...\nThis may take several minutes."
        case .load:
            return "Loading image from tar archive..."
        }
    }
    
    // MARK: - Navigation
    
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
        case .review:
            return true
        }
    }
    
    func nextStep() {
        guard let nextStep = Step(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation {
            currentStep = nextStep
            errorMessage = nil
        }
    }
    
    func previousStep() {
        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation {
            currentStep = previousStep
            errorMessage = nil
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
                // On error, go back to review step and show error
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
        let platform = try Platform(from: platformString)
        let reference = tag.isEmpty ? imageName : "\(imageName):\(tag)"
        
        try await imageManager.pull(reference: reference, platform: platform)
    }
    
    func buildImage() async throws {
        guard let contextDirectory, let dockerFile else {
            throw NSError(domain: "BuildError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing context directory or Dockerfile"])
        }
        
        let platformStringArray: [String] = self.buildPlatformString.split(separator: ",").map({$0.trimmingCharacters(in: .whitespacesAndNewlines)})
        
        var platforms: Set<Platform> = Set(try platformStringArray.map({try Platform(from: $0)}))
        
        if platforms.isEmpty {
            platforms.insert(Platform.current)
        }
        
        let validBuildArguments = self.buildArguments.filter({!$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty})
        
        try await imageManager.build(
            dockerFile: dockerFile,
            contextDirectory: contextDirectory,
            tag: buildTag,
            cpus: 2,
            memory: 1024.mib(),
            vSockPort: 8088,
            outputs: [BuildImageOutputConfiguration(type: .oci, additionalFields: [])],
            platforms: platforms,
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
            throw NSError(domain: "LoadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No tar file selected"])
        }
        
        try await imageManager.load(tar: tarFile)
    }
}
