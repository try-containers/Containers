//
//  Mount.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import Foundation

enum MountError: LocalizedError {
    case targetMissing
    case targetNotAbsolute
    case sourceNotAbsolute
    case duplicateTarget(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing:
            "Mounts require a target."
        case .targetNotAbsolute:
            "Mount target must be absolute."
        case .sourceNotAbsolute:
            "Mount source must be an absolute host path."
        case .duplicateTarget(let target):
            "A mount already exists at \(target)."
        }
    }
}

struct Mount: Identifiable {
    let id: UUID = UUID()
    var hostPath: String = ""
    var containerPath: String = ""

    var summary: String {
        if trimmedSource.isEmpty && trimmedTarget.isEmpty {
            return "New Mount"
        }

        if trimmedSource.isEmpty {
            return trimmedTarget.isEmpty
                ? "Temporary Mount" : "Temporary Mount -> \(trimmedTarget)"
        }

        return trimmedTarget.isEmpty
            ? trimmedSource : "\(trimmedSource) -> \(trimmedTarget)"
    }

    var columns: [String] {
        [
            trimmedSource.isEmpty ? "Temporary Mount" : trimmedSource,
            trimmedTarget,
        ]
    }

    var trimmedSource: String {
        hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTarget: String {
        containerPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
