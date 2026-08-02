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
        VStack(alignment: .leading, spacing: 24) {
            registryFeaturedImageView

            EditableField(
                title: "Registry",
                placeholder: "Registry",
                options: Registry.allCases,
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
        max(1, (registryFeaturedImages.count + featuredImagesPerPage - 1) / featuredImagesPerPage)
    }

    private var currentPageImages: [ImageSuggestion] {
        let start = featuredImagePage * featuredImagesPerPage
        let end = min(start + featuredImagesPerPage, registryFeaturedImages.count)
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
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func registryField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        EditableFormRow {
            Text("\(title):")
        } control: {
            content()
        }
    }

    private var registryImageNameField: some View {
        registryField(title: "Image Name") {
            TextField("Ex: nginx, ubuntu, redis", text: $imageName)
                .suggestions(for: isImageNameFieldFocused ? imageName : nil) {
                    [client = registry.client] text in
                    try await client.images(matching: text)
                        .filter { $0 != text }
                }
                .textFieldStyle(.roundedBorder)
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
                .suggestions(for: isTagFieldFocused ? tag : nil) {
                    [client = registry.client, imageName] text in
                    try await client.tags(for: imageName, matching: text)
                }
                .textFieldStyle(.roundedBorder)
                .focused($isTagFieldFocused)
        }
    }

    @ViewBuilder
    private func registryImageArtwork(for image: ImageSuggestion)
        -> some View
    {
        if let url = image.imageURL {
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
