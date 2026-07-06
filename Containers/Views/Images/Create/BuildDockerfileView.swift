//
//  BuildDockerfileView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerSystem
import ContainerizationOCI
import SwiftUI
import UniformTypeIdentifiers

struct BuildDockerfileView: View {
    let defaultFileDialogDirectory: URL?

    @Binding var errorMessage: String?
    @Binding var contextDirectory: URL?
    @Binding var dockerFile: URL?
    @Binding var buildTag: String
    @Binding var buildPlatform: PlatformSelection
    @Binding var buildArguments: [KeyValue]
    @Binding var targetStage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            FileSelection(
                title: "Dockerfile",
                placeholder: "No Dockerfile selected",
                fileURL: $dockerFile,
                allowedContentTypes: [.item],
                defaultDirectory: defaultFileDialogDirectory,
                onSelection: { errorMessage = nil }
            )

            FileSelection(
                title: "Build Directory",
                placeholder: "No build directory selected",
                fileURL: $contextDirectory,
                canChooseDirectories: true,
                defaultDirectory: defaultFileDialogDirectory,
                onSelection: { errorMessage = nil }
            )
            .onChange(
                of: contextDirectory,
                {
                    guard let url = contextDirectory, dockerFile == nil
                    else { return }
                    // Auto-suggest Dockerfile in the build directory.
                    let dockerfileURL = url.appending(path: "Dockerfile")
                    if FileManager.default.fileExists(
                        atPath: dockerfileURL.path
                    ) {
                        self.dockerFile = dockerfileURL
                    }
                }
            )

            EditableField(
                title: "Image Name",
                description: "⭑ If empty, a generated UUID will be used",
                placeholder: "Ex: my-app, my-app:dev",
                value: $buildTag
            )

            EditableField(
                title: "Platform",
                placeholder: "Platform",
                options: platformOptions,
                selection: $buildPlatform
            )

            EditableField(
                title: "Target Stage (Optional)",
                placeholder: "Ex: production",
                value: $targetStage
            )
        }
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

}
