//
//  RegistryClient.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Foundation

/// Why a lookup could not be answered. Distinguishes a registry that would not
/// talk to us from one that simply had nothing to suggest.
enum RegistryError: LocalizedError {
    case rateLimited
    case unavailable

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            "The registry is rate limiting requests. Suggestions will come back shortly."
        case .unavailable:
            "Couldn't reach the registry."
        }
    }
}

/// The lookups a registry can answer while the image and tag fields are typed
/// into. How a name maps onto the registry's own API is the client's business.
protocol RegistryClient: Sendable {
    func images(matching text: String) async throws -> [String]
    func tags(for imageName: String, matching text: String) async throws -> [String]
    func trendingImages() async throws -> [ImageSuggestion]
}

extension Registry {
    /// The client that answers this registry's lookups.
    var client: any RegistryClient {
        switch self {
        case .dockerHub:
            DockerHub()
        }
    }
}
