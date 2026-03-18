//
//  ClientImage.swift
//  Containers
//
//  Utility for image reference normalization.
//

import Foundation
import ContainerizationOCI

/// Utility for working with container image references.
public enum ClientImage {
    
    /// The default init image reference.
    public static var initImageRef: String {
        DefaultsStore.get(key: .defaultInitImage)
    }
    
    /// Normalize a short image reference to a fully qualified reference.
    /// Adds `docker.io/library/` prefix for short names and `:latest` tag if missing.
    public static func normalizeReference(_ reference: String) throws -> String {
        // Use the OCI Reference parser for proper normalization
        let parsed = try Reference.parse(reference)
        parsed.normalize()
        return parsed.description
    }
}
