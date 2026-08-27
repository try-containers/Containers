//
//  CreateImageConfiguration.swift
//  Containers
//
//  Created by Axel Martinez on 28/06/2026.
//

import ContainerSystem
import ContainerizationOCI
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CreateImageConfiguration: View {
    let selectedMethod: CreateImageView.CreationMethod?
    let defaultFileDialogDirectory: URL?
    let tarContentTypes: [UTType]
    let shouldLoadPullFeaturedImages: Bool
    let onFileSelection: () -> Void

    @Binding var error: ErrorAlert?
    @Binding var imageName: String
    @Binding var tag: String
    @Binding var pullPlatform: PlatformSelection
    @Binding var contextDirectory: URL?
    @Binding var dockerFile: URL?
    @Binding var buildTag: String
    @Binding var buildPlatform: PlatformSelection
    @Binding var buildArguments: [KeyValue]
    @Binding var targetStage: String
    @Binding var tarFile: URL?
    @Binding var forceLoad: Bool

    var body: some View {
        Group {
            switch selectedMethod {
            case .pull:
                PullImageView(
                    shouldLoadFeaturedImages: shouldLoadPullFeaturedImages,
                    imageName: $imageName,
                    tag: $tag,
                    platform: $pullPlatform
                )
            case .build:
                BuildDockerfileView(
                    defaultFileDialogDirectory: defaultFileDialogDirectory,
                    error: $error,
                    contextDirectory: $contextDirectory,
                    dockerFile: $dockerFile,
                    buildTag: $buildTag,
                    buildPlatform: $buildPlatform,
                    buildArguments: $buildArguments,
                    targetStage: $targetStage
                )
            case .load:
                LoadTarImageView(
                    tarFile: $tarFile,
                    force: $forceLoad,
                    tarContentTypes: tarContentTypes,
                    defaultDirectory: defaultFileDialogDirectory,
                    onSelection: onFileSelection
                )
            case .none:
                EmptyView()
            }
        }
    }
}
