//
//  ImageInspect.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import ContainerSystem
import SwiftUI

struct ImageInspect: View {
    let image: ImageViewModel
    
    @Environment(ImageManager.self) private var imageManager
    
    @State private var printable: ContainerSystem.ImageResource?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let printable {
                InspectView(value: printable)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Inspect Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: image.id) {
            await loadInspectDetail()
        }
    }
    
    private func loadInspectDetail() async {
        errorMessage = nil
        
        do {
            printable = try await imageManager.inspect(image: image.imageDescription)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
