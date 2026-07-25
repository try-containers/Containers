//
//  DockerHub.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import Foundation

enum DockerHubRegistrySuggestions {
    private struct FeaturedResponse: Decodable {
        let summaries: [FeaturedImage]?
        let results: [FeaturedImage]?
    }

    private struct FeaturedImage: Decodable {
        let name: String?
        let slug: String?
        let shortDescription: String?
        let description: String?
        let publisher: String?
        let publisherName: String?
        let imageURL: String?
        let logoURL: String?
        let thumbnailURL: String?
        let iconURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case slug
            case shortDescription = "short_description"
            case description
            case publisher
            case publisherName = "publisher_name"
            case imageURL = "image_url"
            case logoURL = "logo_url"
            case thumbnailURL = "thumbnail_url"
            case iconURL = "icon_url"
            case image
            case logo
            case thumbnail
            case icon
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = Self.decodeString(from: container, forKey: .name)
            slug = Self.decodeString(from: container, forKey: .slug)
            shortDescription = Self.decodeString(
                from: container,
                forKey: .shortDescription
            )
            description = Self.decodeString(
                from: container,
                forKey: .description
            )
            publisher = Self.decodeString(from: container, forKey: .publisher)
            publisherName = Self.decodeString(
                from: container,
                forKey: .publisherName
            )
            imageURL =
                Self.decodeString(from: container, forKey: .imageURL)
                ?? Self.decodeString(from: container, forKey: .image)
            logoURL =
                Self.decodeString(from: container, forKey: .logoURL)
                ?? Self.decodeString(from: container, forKey: .logo)
            thumbnailURL =
                Self.decodeString(from: container, forKey: .thumbnailURL)
                ?? Self.decodeString(from: container, forKey: .thumbnail)
            iconURL =
                Self.decodeString(from: container, forKey: .iconURL)
                ?? Self.decodeString(from: container, forKey: .icon)
        }

        private static func decodeString(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }

        var suggestion: ImageSuggestion? {
            guard let imageName = slug ?? name else {
                return nil
            }

            return ImageSuggestion(
                name: imageName,
                publisher: publisherName ?? publisher,
                description: shortDescription ?? description,
                imageURL: [imageURL, thumbnailURL, iconURL, logoURL]
                    .compactMap {
                        $0?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .first { !$0.isEmpty }
                    .flatMap(URL.init(string:))
            )
        }
    }

    private struct ImageSearchResponse: Decodable {
        let results: [ImageSearchResult]
    }

    private struct ImageSearchResult: Decodable {
        let repoName: String

        enum CodingKeys: String, CodingKey {
            case repoName = "repo_name"
        }
    }

    private struct TagResponse: Decodable {
        let results: [Tag]
    }

    private struct Tag: Decodable {
        let name: String
    }

    private struct RepositoryDetail: Decodable {
        let fullDescription: String?

        enum CodingKeys: String, CodingKey {
            case fullDescription = "full_description"
        }
    }

    static func canSuggestImages(for imageName: String) -> Bool {
        let components =
            imageName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let first = components.first else {
            return false
        }

        if RegistryReference.isExplicitRegistry(first) {
            return RegistryReference.isDockerHubRegistry(first)
        }

        return components.count <= 2
    }

    static func trendingImages() async throws
        -> [ImageSuggestion]
    {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        components.path = "/api/content/v1/products/search"
        components.queryItems = [
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "q", value: ""),
            URLQueryItem(name: "source", value: "community"),
            URLQueryItem(name: "type", value: "image,model"),
            URLQueryItem(name: "sort", value: "trending"),
        ]

        guard let url = components.url else {
            return fallbackTrendingImages
        }

        do {
            let decoded: FeaturedResponse = try await fetch(url: url)
            let products = decoded.summaries ?? decoded.results ?? []
            let suggestions = products.compactMap(\.suggestion)
            let images = suggestions.isEmpty ? fallbackTrendingImages : suggestions

            return await suggestionsWithRepositoryLogos(images)
        } catch {
            return await suggestionsWithRepositoryLogos(fallbackTrendingImages)
        }
    }

    static func repository(from imageName: String) -> RegistryRepository? {
        var components =
            imageName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !components.isEmpty else {
            return nil
        }

        if let host = components.first,
            RegistryReference.isExplicitRegistry(host)
        {
            guard RegistryReference.isDockerHubRegistry(host) else {
                return nil
            }

            components.removeFirst()
        }

        guard !components.isEmpty else {
            return nil
        }

        let namespace: String
        let name: String
        if components.count == 1 {
            namespace = "library"
            name = RegistryReference.repositoryName(from: components[0])
        } else if components.count == 2 {
            namespace = components[0]
            name = RegistryReference.repositoryName(from: components[1])
        } else {
            return nil
        }

        guard !namespace.isEmpty, !name.isEmpty else {
            return nil
        }

        return RegistryRepository(namespace: namespace, name: name)
    }

    static func images(matching query: String) async throws -> [String] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        components.path = "/v2/search/repositories/"
        components.queryItems = [
            URLQueryItem(name: "query", value: normalizedSearchQuery(query)),
            URLQueryItem(name: "page_size", value: "10"),
        ]

        guard let url = components.url else {
            return []
        }

        let decoded: ImageSearchResponse = try await fetch(url: url)
        return decoded.results.map(\.repoName)
    }

    static func tags(
        for repository: RegistryRepository,
        matching prefix: String
    ) async throws -> [String] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        components.path =
            "/v2/repositories/\(repository.namespace)/\(repository.name)/tags/"
        components.queryItems = [
            URLQueryItem(name: "page_size", value: "20")
        ]

        if !prefix.isEmpty {
            components.queryItems?.append(
                URLQueryItem(name: "name", value: prefix)
            )
        }

        guard let url = components.url else {
            return []
        }

        let decoded: TagResponse = try await fetch(url: url)
        return decoded.results.map(\.name)
    }

    private static func suggestionsWithRepositoryLogos(
        _ suggestions: [ImageSuggestion]
    ) async -> [ImageSuggestion] {
        await withTaskGroup(of: (Int, ImageSuggestion).self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                group.addTask {
                    guard suggestion.imageURL == nil,
                        let logoURL = await repositoryLogoURL(for: suggestion.name)
                    else {
                        return (index, suggestion)
                    }

                    return (
                        index,
                        ImageSuggestion(
                            name: suggestion.name,
                            publisher: suggestion.publisher,
                            description: suggestion.description,
                            imageURL: logoURL
                        )
                    )
                }
            }

            var enriched = suggestions
            for await (index, suggestion) in group {
                enriched[index] = suggestion
            }
            return enriched
        }
    }

    private static func repositoryLogoURL(for imageName: String) async -> URL? {
        guard let repository = repository(from: imageName) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "hub.docker.com"
        components.path =
            "/v2/repositories/\(repository.namespace)/\(repository.name)/"

        guard let url = components.url else {
            return nil
        }

        do {
            let detail: RepositoryDetail = try await fetch(url: url)
            return firstMarkdownImageURL(in: detail.fullDescription)
        } catch {
            return nil
        }
    }

    private static func firstMarkdownImageURL(in markdown: String?) -> URL? {
        guard let markdown else { return nil }

        let pattern = #"!\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        guard let match = regex.firstMatch(in: markdown, range: range),
            match.numberOfRanges > 1,
            let urlRange = Range(match.range(at: 1), in: markdown)
        else {
            return nil
        }

        let value = String(markdown[urlRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: value)
    }

    private static func normalizedSearchQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let components =
            trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let first = components.first,
            RegistryReference.isDockerHubRegistry(first)
        else {
            return trimmed
        }

        return components.dropFirst().joined(separator: "/")
    }

    private static func fetch<Response: Decodable>(url: URL) async throws
        -> Response
    {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static var fallbackTrendingImages: [ImageSuggestion] {
        [
            .init(
                name: "ai/qwen3",
                publisher: "Docker",
                description: "Qwen3 model images",
                imageURL: nil
            ),
            .init(
                name: "arm32v7/redis",
                publisher: "arm32v7",
                description: "Redis for arm32v7",
                imageURL: nil
            ),
            .init(
                name: "hylang",
                publisher: "Docker Official Image",
                description: "Hy language image",
                imageURL: nil
            ),
            .init(
                name: "atlassian/confluence",
                publisher: "Atlassian",
                description: "Confluence image",
                imageURL: nil
            ),
        ]
    }
}

enum RegistryReference {
    static func isExplicitRegistry(_ component: String) -> Bool {
        component.contains(".")
            || component.contains(":")
            || component == "localhost"
    }

    static func isDockerHubRegistry(_ host: String) -> Bool {
        host == "docker.io"
            || host == "index.docker.io"
            || host == "registry-1.docker.io"
    }

    static func repositoryName(from value: String) -> String {
        value
            .split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            .first
            .map(String.init) ?? value
    }
}

struct RegistryRepository: Sendable {
    let namespace: String
    let name: String
}
