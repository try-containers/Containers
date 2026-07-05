//
//  ClientImage.swift
//  Containers
//
//  Utility for image reference normalization.
//

import ContainerizationOCI
import Foundation

/// Utility for working with container image references.
public enum ClientImage {

    /// The default init image reference.
    public static var initImageRef: String {
        DefaultsStore.get(key: .defaultInitImage)
    }

    /// Normalize a short image reference to a fully qualified reference.
    /// Adds `docker.io/library/` prefix for Docker Hub official images and `:latest` tag if missing.
    public static func normalizeReference(
        _ reference: String
    ) throws -> String {
        let trimmedReference = reference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let parsed = try Reference.parse(trimmedReference)
        parsed.normalize()

        let normalizedReference = parsed.description
        let normalizedParsed = try Reference.parse(normalizedReference)
        if normalizedParsed.domain != nil {
            return normalizedReference
        }

        let dockerHubReference: String
        if normalizedReference.contains("/") {
            let firstComponent =
                normalizedReference.split(separator: "/", maxSplits: 1).first
                .map(String.init) ?? ""
            let hasExplicitRegistry =
                firstComponent.contains(".") || firstComponent.contains(":")
                || firstComponent == "localhost"
            guard !hasExplicitRegistry else {
                return normalizedReference
            }

            dockerHubReference = "docker.io/\(normalizedReference)"
        } else {
            dockerHubReference = "docker.io/library/\(normalizedReference)"
        }

        let dockerHubParsed = try Reference.parse(dockerHubReference)
        dockerHubParsed.normalize()
        return dockerHubParsed.description
    }
}
