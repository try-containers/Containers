//
//  PullImageView.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import ContainerizationOCI
import SwiftUI

struct PullImageView: View {
    let shouldLoadFeaturedImages: Bool

    @Binding var imageName: String
    @Binding var tag: String
    @Binding var platform: PlatformSelection

    @SwiftUI.State private var registry: Registry = .dockerHub
    @SwiftUI.State private var registryFeaturedImages: [ImageSuggestion] = []
    @SwiftUI.State private var registryFeaturedImageTask: Task<Void, Never>?
    @SwiftUI.State private var featuredImagePage: Int = 0
    @SwiftUI.State private var isLoadingRegistryFeaturedImages: Bool = false

    @FocusState private var isImageNameFieldFocused: Bool
    @FocusState private var isTagFieldFocused: Bool

    var body: some View {
        FormStack {
            featuredImageContent
                .frame(height: 132, alignment: .topLeading)
        } content: {
            FormRow(title: "Registry") {
                FormPicker(
                    placeholder: "Registry",
                    options: Registry.allCases,
                    selection: $registry
                )
            }

            registryImageNameField

            registryTagField

            FormRow(title: "Platform") {
                FormPicker(
                    placeholder: "Platform",
                    options: platformOptions,
                    selection: $platform
                )
            }
        }
        .onChange(of: shouldLoadFeaturedImages, initial: true) {
            _,
            shouldLoad in
            guard shouldLoad else { return }
            loadRegistryFeaturedImages()
        }
        .onChange(of: registry) {
            refreshRegistryData()
        }
        .onDisappear {
            registryFeaturedImageTask?.cancel()
        }
    }

    private var platformOptions: [PlatformSelection] {
        var options: [PlatformSelection] = [.any, .platform(.current)]

        if Platform.current.architecture == "arm64" {
            options.append(.platform(Platform(arch: "amd64", os: "linux")))
        }

        return options
    }

    private let featuredImagesPerPage = 5

    private var featuredPageCount: Int {
        max(
            1,
            (registryFeaturedImages.count + featuredImagesPerPage - 1)
                / featuredImagesPerPage
        )
    }

    private var currentPageImages: [ImageSuggestion] {
        let start = featuredImagePage * featuredImagesPerPage
        let end = min(
            start + featuredImagesPerPage,
            registryFeaturedImages.count
        )
        guard start < end else { return [] }
        return Array(registryFeaturedImages[start..<end])
    }

    /// A publisher's repositories often scrape the same logo, and a row of
    /// identical icons reads as a bug. Drop the artwork they share so those
    /// fall back to initials, keeping the ones that are actually distinct.
    ///
    /// Done once as the images arrive: as a computed property this ran for
    /// every card on every redraw.
    private func withoutSharedArtwork(
        _ images: [ImageSuggestion]
    ) -> [ImageSuggestion] {
        let counts = images.reduce(into: [URL: Int]()) { counts, image in
            if let url = image.imageURL {
                counts[url, default: 0] += 1
            }
        }

        return images.map { image in
            guard let url = image.imageURL, counts[url, default: 0] > 1 else {
                return image
            }

            return ImageSuggestion(
                name: image.name,
                publisher: image.publisher,
                description: image.description,
                imageURL: nil
            )
        }
    }

    private func featuredPageButton(
        _ systemName: String,
        step: Int,
        isDisabled: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                featuredImagePage += step
            }
        } label: {
            Image(systemName: systemName)
                .imageScale(.large)
                .foregroundStyle(
                    isDisabled ? Color(nsColor: .separatorColor) : .secondary
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var featuredImageContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending this week on \(registry.description)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !registryFeaturedImages.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(currentPageImages) { image in
                        FeaturedImageCard(image: image) {
                            selectRegistryImage(image.name)
                        }
                    }
                }
                // Overlaid rather than placed alongside, so the cards keep the
                // full width, and pushed back out past the edges so they sit
                // clear of them: a form row is narrower than the sheet.
                .overlay {
                    if featuredPageCount > 1 {
                        HStack(spacing: 0) {
                            featuredPageButton(
                                "arrow.left.circle.fill",
                                step: -1,
                                isDisabled: featuredImagePage == 0
                            )

                            Spacer(minLength: 0)

                            featuredPageButton(
                                "arrow.right.circle.fill",
                                step: 1,
                                isDisabled: featuredImagePage
                                    >= featuredPageCount - 1
                            )
                        }
                        .padding(.horizontal, -28)
                    }
                }
            } else if isLoadingRegistryFeaturedImages {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 108)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var registryImageNameField: some View {
        FormRow(title: "Image Name") {
            TextField(
                text: $imageName,
                prompt: Text("Ex: nginx, ubuntu, redis")
            ) {
                EmptyView()
            }
            .suggestions(for: isImageNameFieldFocused ? imageName : nil) {
                [client = registry.client] text in
                try await client.images(matching: text)
                    .filter { $0 != text }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($isImageNameFieldFocused)
            .onChange(of: imageName) { oldValue, newValue in
                // A new image invalidates the tag, but refreshing the tag
                // suggestions is the tag field's job, not this one's.
                if oldValue != newValue, tag != "latest" {
                    tag = "latest"
                }
            }
        }
    }

    private func selectRegistryImage(_ name: String) {
        isImageNameFieldFocused = false
        isTagFieldFocused = false
        imageName = name
        tag = "latest"
    }

    @ViewBuilder
    private var registryTagField: some View {
        FormRow(title: "Tag") {
            TextField(
                text: $tag,
                prompt: Text("Ex: latest, 1.0, stable")
            ) {
                EmptyView()
            }
            .suggestions(for: isTagFieldFocused ? tag : nil) {
                [client = registry.client, imageName] text in
                try await client.tags(for: imageName, matching: text)
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($isTagFieldFocused)
        }
    }

    private func refreshRegistryData() {
        registryFeaturedImageTask?.cancel()
        registryFeaturedImageTask = nil
        registryFeaturedImages = []
        featuredImagePage = 0
        isLoadingRegistryFeaturedImages = false

        if shouldLoadFeaturedImages {
            loadRegistryFeaturedImages()
        }
    }

    private func loadRegistryFeaturedImages() {
        guard registryFeaturedImages.isEmpty, registryFeaturedImageTask == nil
        else {
            return
        }

        let client = registry.client

        registryFeaturedImageTask = Task {
            await MainActor.run {
                isLoadingRegistryFeaturedImages = true
            }

            do {
                let images = try await client.trendingImages()

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    registryFeaturedImages = withoutSharedArtwork(images)
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

}

private struct FeaturedImageCard: View {
    let image: ImageSuggestion
    let action: () -> Void

    private let artworkSize: CGFloat = 44
    private let artworkRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                artwork
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(shape)

                VStack(spacing: 1) {
                    Text(image.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    // Kept in the layout when absent so every card is the
                    // same height whatever the registry returns.
                    Group {
                        if let publisher = image.publisher {
                            Text(publisher)
                        } else {
                            Text("Publisher").hidden()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background {
                card.fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            }
            .overlay(card.strokeBorder(.quaternary, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = image.imageURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                initials
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        Text(initialsText)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.18))
    }

    private var initialsText: String {
        let components = image.name
            .split(separator: "/", omittingEmptySubsequences: true)
            .suffix(2)

        let initials = components.compactMap { $0.first.map(String.init) }
            .joined()

        return initials.isEmpty ? "I" : initials.uppercased()
    }

    private var tint: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let value = image.name.unicodeScalars.reduce(0) { result, scalar in
            result + Int(scalar.value)
        }

        return colors[value % colors.count]
    }
}
