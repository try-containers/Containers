//
//  ImageSuggestion.swift
//  Containers
//
//  Created by Axel Martinez on 27/06/2026.
//

import Foundation

struct ImageSuggestion: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let publisher: String?
    let description: String?
    let imageURL: URL?
}
