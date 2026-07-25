//
//  PullImageView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerizationOCI
import SwiftUI

struct PullImageView: View {
    private enum Registry: Hashable, CustomStringConvertible {
        case dockerHub

        var description: String {
            switch self {
            case .dockerHub:
                "Docker Hub"
            }
        }
    }

    let shouldLoadFeaturedImages: Bool

    @Binding var imageName: String
    @Binding var tag: String
    @Binding var platform: PlatformSelection

    @SwiftUI.State private var registry: Registry = .dockerHub
    @SwiftUI.State private var registryFeaturedImages: [ImageSuggestion] = []
    @SwiftUI.State private var registryFeaturedImageTask: Task<Void, Never>?
    @SwiftUI.State private var featuredImagePage: Int = 0
    @SwiftUI.State private var registryImageSuggestions: [String] = []
    @SwiftUI.State private var registryImageSuggestionTask: Task<Void, Never>?
    @SwiftUI.State private var registryTagSuggestions: [String] = []
    @SwiftUI.State private var registryTagSuggestionTask: Task<Void, Never>?
    @SwiftUI.State private var isLoadingRegistryImages: Bool = false
    @SwiftUI.State private var isLoadingRegistryFeaturedImages: Bool = false
    @SwiftUI.State private var isLoadingRegistryTags: Bool = false

    @FocusState private var isImageNameFieldFocused: Bool
    @FocusState private var isTagFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            registryFeaturedImageView

            EditableField(
                title: "Registry",
                placeholder: "Registry",
                options: [.dockerHub],
                selection: $registry
            )

            registryImageNameField

            registryTagField

            EditableField(
                title: "Platform",
                placeholder: "Platform",
                options: platformOptions,
                selection: $platform
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onChange(of: shouldLoadFeaturedImages, initial: true) { _, shouldLoad in
            guard shouldLoad else { return }
            loadRegistryFeaturedImages()
        }
        .onChange(of: registry) {
            refreshRegistryData()
        }
        .onDisappear {
            registryFeaturedImageTask?.cancel()
            registryImageSuggestionTask?.cancel()
            registryTagSuggestionTask?.cancel()
        }
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.any, .platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

    private var registrySuggestionProvider: RegistrySuggestionProvider? {
        switch registry {
        case .dockerHub:
            RegistrySuggestionProvider.provider(for: imageName)
        }
    }

    private let featuredImagesPerPage = 5

    private var featuredPageCount: Int {
        max(1, (registryFeaturedImages.count + featuredImagesPerPage - 1) / featuredImagesPerPage)
    }

    private var currentPageImages: [ImageSuggestion] {
        let start = featuredImagePage * featuredImagesPerPage
        let end = min(start + featuredImagesPerPage, registryFeaturedImages.count)
        guard start < end else { return [] }
        return Array(registryFeaturedImages[start..<end])
    }

    private var duplicateFeaturedImageURLs: Set<URL> {
        let urls = registryFeaturedImages.compactMap(\.imageURL)
        let groupedURLs = Dictionary(grouping: urls, by: { $0 })
        return Set(
            groupedURLs.compactMap { url, matches in
                matches.count > 1 ? url : nil
            }
        )
    }

    @ViewBuilder
    private var registryFeaturedImageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trending this week on \(registry.description)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !registryFeaturedImages.isEmpty {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            featuredImagePage -= 1
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .imageScale(.large)
                            .foregroundStyle(featuredImagePage == 0 ? Color(nsColor: .separatorColor) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(featuredImagePage == 0)

                    HStack(spacing: 8) {
                        ForEach(currentPageImages) { image in
                            Button {
                                selectRegistryImage(image.name)
                            } label: {
                                VStack(alignment: .center, spacing: 6) {
                                    registryImageArtwork(for: image)

                                    Text(image.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)

                                    if let publisher = image.publisher {
                                        Text(publisher)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 92)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(nsColor: .separatorColor))
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            featuredImagePage += 1
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .imageScale(.large)
                            .foregroundStyle(featuredImagePage >= featuredPageCount - 1 ? Color(nsColor: .separatorColor) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(featuredImagePage >= featuredPageCount - 1)
                }
            } else if isLoadingRegistryFeaturedImages {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 108)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(
            width: EditableFormLayout.labelWidth
                + EditableFormLayout.controlWidth,
            height: 132,
            alignment: .topLeading
        )
    }

    private func registryField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top) {
            Text("\(title):")
                .frame(
                    width: EditableFormLayout.labelWidth,
                    alignment: .trailing
                )
                .padding(.top, EditableFormLayout.fieldLabelTopPadding)

            content()
                .frame(
                    width: EditableFormLayout.controlWidth,
                    alignment: .leading
                )
        }
    }

    private var registryImageNameField: some View {
        registryField(title: "Image Name") {
            TextField("Ex: nginx, ubuntu, redis", text: $imageName)
                .textFieldStyle(.roundedBorder)
                .focused($isImageNameFieldFocused)
                .overlay(alignment: .trailing) {
                    if isLoadingRegistryImages {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 6)
                    }
                }
                .textInputSuggestions {
                    ForEach(registryImageSuggestions, id: \.self) {
                        suggestion in
                        Text(suggestion)
                            .textInputCompletion(suggestion)
                    }
                }
                .onChange(of: imageName) { oldValue, newValue in
                    let didSelectSuggestion =
                        registryImageSuggestions.contains(newValue)
                    if didSelectSuggestion {
                        clearRegistryImageSuggestions()
                    }

                    if oldValue != newValue, tag != "latest" {
                        tag = "latest"
                    }

                    guard isImageNameFieldFocused else {
                        clearRegistryImageSuggestions()
                        return
                    }

                    if !didSelectSuggestion {
                        scheduleRegistryImageSuggestions()
                    }
                    scheduleRegistryTagSuggestions()
                }
                .onChange(of: isImageNameFieldFocused) { _, isFocused in
                    if !isFocused {
                        clearRegistryImageSuggestions()
                    }
                }
        }
    }

    private func registryImageFallbackArtwork(for name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(registryImageFallbackColor(for: name).opacity(0.18))

            Text(registryImageInitials(for: name))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(registryImageFallbackColor(for: name))
        }
        .frame(width: 32, height: 32)
    }

    private func registryImageFallbackColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let value = name.unicodeScalars.reduce(0) { result, scalar in
            result + Int(scalar.value)
        }

        return colors[value % colors.count]
    }

    private func selectRegistryImage(_ name: String) {
        isImageNameFieldFocused = false
        isTagFieldFocused = false
        imageName = name
        tag = "latest"
        clearRegistryImageSuggestions()
        clearRegistryTagSuggestions()
    }

    private func registryImageInitials(for name: String) -> String {
        let components =
            name
            .split(separator: "/", omittingEmptySubsequences: true)
            .suffix(2)

        let initials = components.compactMap { component in
            component.first.map(String.init)
        }
        .joined()

        return initials.isEmpty ? "I" : initials.uppercased()
    }

    @ViewBuilder
    private var registryTagField: some View {
        registryField(title: "Tag") {
            TextField("Ex: latest, 1.0, stable", text: $tag)
                .textFieldStyle(.roundedBorder)
                .focused($isTagFieldFocused)
                .overlay(alignment: .trailing) {
                    if isLoadingRegistryTags {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 6)
                    }
                }
                .textInputSuggestions {
                    ForEach(registryTagSuggestions, id: \.self) {
                        suggestion in
                        Text(suggestion)
                            .textInputCompletion(suggestion)
                    }
                }
                .onChange(of: imageName) {
                    if isTagFieldFocused {
                        scheduleRegistryTagSuggestions()
                    } else {
                        clearRegistryTagSuggestions()
                    }
                }
                .onChange(of: tag) { _, newValue in
                    if registryTagSuggestions.contains(newValue) {
                        clearRegistryTagSuggestions()
                    } else if isTagFieldFocused {
                        scheduleRegistryTagSuggestions()
                    } else {
                        clearRegistryTagSuggestions()
                    }
                }
                .onChange(of: isTagFieldFocused) { _, isFocused in
                    if !isFocused {
                        clearRegistryTagSuggestions()
                    }
                }
        }
    }

    @ViewBuilder
    private func registryImageArtwork(for image: ImageSuggestion)
        -> some View
    {
        if let url = image.imageURL, !duplicateFeaturedImageURLs.contains(url) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
        } else {
            registryImageFallbackArtwork(for: image.name)
        }
    }

    private func refreshRegistryData() {
        registryFeaturedImageTask?.cancel()
        registryFeaturedImageTask = nil
        registryFeaturedImages = []
        featuredImagePage = 0
        isLoadingRegistryFeaturedImages = false
        clearRegistryImageSuggestions()
        clearRegistryTagSuggestions()

        if shouldLoadFeaturedImages {
            loadRegistryFeaturedImages()
        }

        if isImageNameFieldFocused {
            scheduleRegistryImageSuggestions()
        }

        if isTagFieldFocused {
            scheduleRegistryTagSuggestions()
        }
    }

    private func loadRegistryFeaturedImages() {
        guard registryFeaturedImages.isEmpty, registryFeaturedImageTask == nil,
            let provider = registrySuggestionProvider
        else {
            return
        }

        registryFeaturedImageTask = Task {
            await MainActor.run {
                isLoadingRegistryFeaturedImages = true
            }

            do {
                let images = try await provider.featuredImages()
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryFeaturedImages = images
                    isLoadingRegistryFeaturedImages = false
                    registryFeaturedImageTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryFeaturedImages = []
                    isLoadingRegistryFeaturedImages = false
                    registryFeaturedImageTask = nil
                }
            }
        }
    }

    private func scheduleRegistryImageSuggestions() {
        registryImageSuggestionTask?.cancel()

        guard let provider = registrySuggestionProvider,
            provider.canSuggestImages(for: imageName),
            !imageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            registryImageSuggestions = []
            isLoadingRegistryImages = false
            return
        }

        let query = imageName.trimmingCharacters(in: .whitespacesAndNewlines)

        registryImageSuggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isLoadingRegistryImages = true
            }

            do {
                let suggestions = try await provider.imageSuggestions(
                    matching: query
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryImageSuggestions = suggestions.filter {
                        $0 != imageName
                    }
                    isLoadingRegistryImages = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryImageSuggestions = []
                    isLoadingRegistryImages = false
                }
            }
        }
    }

    private func scheduleRegistryTagSuggestions() {
        registryTagSuggestionTask?.cancel()

        guard let provider = registrySuggestionProvider,
            provider.canSuggestTags(for: imageName)
        else {
            registryTagSuggestions = []
            isLoadingRegistryTags = false
            return
        }

        let tagPrefix = tag.trimmingCharacters(in: .whitespacesAndNewlines)

        registryTagSuggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isLoadingRegistryTags = true
            }

            do {
                let suggestions = try await provider.tagSuggestions(
                    for: imageName,
                    matching: tagPrefix
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryTagSuggestions = suggestions
                    isLoadingRegistryTags = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryTagSuggestions = []
                    isLoadingRegistryTags = false
                }
            }
        }
    }

    private func clearRegistryImageSuggestions() {
        registryImageSuggestionTask?.cancel()
        registryImageSuggestionTask = nil
        registryImageSuggestions = []
        isLoadingRegistryImages = false
    }

    private func clearRegistryTagSuggestions() {
        registryTagSuggestionTask?.cancel()
        registryTagSuggestionTask = nil
        registryTagSuggestions = []
        isLoadingRegistryTags = false
    }

    private enum RegistrySuggestionProvider: Sendable {
        case dockerHub

        static func provider(for imageName: String) -> Self? {
            let components =
                imageName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)

            guard let first = components.first else {
                return .dockerHub
            }

            guard RegistryReference.isExplicitRegistry(first) else {
                return .dockerHub
            }

            return RegistryReference.isDockerHubRegistry(first)
                ? .dockerHub : nil
        }

        func canSuggestImages(for imageName: String) -> Bool {
            switch self {
            case .dockerHub:
                return DockerHubRegistrySuggestions.canSuggestImages(
                    for: imageName
                )
            }
        }

        func canSuggestTags(for imageName: String) -> Bool {
            switch self {
            case .dockerHub:
                return DockerHubRegistrySuggestions.repository(from: imageName)
                    != nil
            }
        }

        func imageSuggestions(matching query: String) async throws -> [String] {
            switch self {
            case .dockerHub:
                return try await DockerHubRegistrySuggestions.images(
                    matching: query
                )
            }
        }

        func tagSuggestions(for imageName: String, matching prefix: String)
            async throws -> [String]
        {
            switch self {
            case .dockerHub:
                guard
                    let repository = DockerHubRegistrySuggestions.repository(
                        from: imageName
                    )
                else {
                    return []
                }

                return try await DockerHubRegistrySuggestions.tags(
                    for: repository,
                    matching: prefix
                )
            }
        }

        func featuredImages() async throws -> [ImageSuggestion] {
            switch self {
            case .dockerHub:
                return try await DockerHubRegistrySuggestions.trendingImages()
            }
        }
    }

}
