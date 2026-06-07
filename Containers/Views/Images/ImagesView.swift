//
//  ImagesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import Containerization
import ContainerSystem
import ContainerizationOCI


struct ImagesView: View {
    @Environment(ImageManager.self) private var imageManager
    @Environment(SystemManager.self) private var system
    
    @Binding var searchText: String
    var refreshTrigger: Int
    
    var onRefresh: (() async -> Void)? = nil
    
    @SwiftUI.State private var images: [ImageViewModel] = []
    @SwiftUI.State private var lastUpdated: Date? = nil
    @SwiftUI.State private var createContainerForImage: ImageViewModel? = nil
    @SwiftUI.State private var imagesToSave: String =  ""
    @SwiftUI.State private var imageToDelete: ImageViewModel?
    @SwiftUI.State private var error: Error?
    @SwiftUI.State private var showError: Bool = false
    @SwiftUI.State private var showDeleteConfirmation: Bool = false
    @SwiftUI.State private var showInUseContainerForImage: ImageViewModel?
    @SwiftUI.State private var showSaveImage: Bool = false
    @SwiftUI.State private var showImageDetails: ImageViewModel?
    
    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredImages: [ImageViewModel] {
        if trimmedText.isEmpty {
            return images
        }
        
        let filtered = self.images.filter({
            $0.name.contains(trimmedText) ||
            $0.tag.contains(trimmedText)
        })
        
        return filtered
    }
    
    
    var body: some View {
        VStack(alignment: .leading , spacing: 0) {
            if system.isRunning {
                Table(of: ImageViewModel.self, columns: {
                    TableColumn("Name") { image in
                        Button(action: {
                            self.showImageDetails = image
                        }) {
                            Text(image.name)
                                .lineLimit(1)
                        }
                        .buttonStyle(.link)
                        .pointerStyle(.link)
                        .underline()
                        .frame(height: 36) // to set minimum row height
                    }
                    .width(min: 150, ideal: 80)
                    
                    TableColumn("Tag") { image in
                        Text(image.tag)
                            .lineLimit(1)
                    }
                    .width(min: 50, ideal: 60)
                    
                    TableColumn("Digest") { image in
                        Text(image.formattedDigest)
                            .lineLimit(1)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 100, ideal: 120, max: 140)
                    
                    TableColumn("State") { image in
                        
                        Group {
                            if image.inUse {
                                Button(action: {
                                    showInUseContainerForImage = image
                                }, label: {
                                    Text("In use")
                                        .lineLimit(1)
                                        .underline()
                                    
                                })
                                .buttonStyle(.link)
                                .pointerStyle(.link)
                            } else {
                                Text("Unused")
                            }
                        }
                        .lineLimit(1)
                        
                    }
                    .width(min: 60, ideal: 70)
                    
                    TableColumn("Actions") { image in
                        
                        HStack(spacing: 12) {
                            
                            Button(action: {
                                self.createContainerForImage = image
                            }, label: {
                                Image(systemName: "cube.fill")
                                    .foregroundStyle(.blue)
                            })
                            .buttonStyle(.plain)
                            .help("Create container from image")
                            
                            Button(action: {
                                imageToDelete = image
                                showDeleteConfirmation = true
                            }, label: {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(image.inUse ? .secondary : Color.red)
                            })
                            .disabled(image.inUse)
                            .buttonStyle(.plain)
                            .help("Delete image")
                            
                        }
                        .padding(.horizontal, 8)
                    }
                    .width(128)

                }, rows: {
                    ForEach(filteredImages)
                })
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .overlay(alignment: .center, content: {
                    if filteredImages.isEmpty {
                        ContentUnavailableView(
                            trimmedText.isEmpty ? "No Images Found" : "No Matching Images",
                            systemImage: NavigationTab.images.icon
                        )
                    }
                })
            } else {
                ContainerSystemView()
            }
        }
        .onChange(of: self.system.isRunning, initial: true, {
            guard self.system.isRunning else {
                self.images = []
                self.lastUpdated = nil
                return
            }
            
            Task {
                guard self.lastUpdated == nil else {
                    return
                }
                
                await self.listImages()
            }
        })
        .onChange(of: refreshTrigger) {
            Task {
                await self.listImages()
            }
        }
        .onAppear {
            Task {
                guard system.isRunning else { return }
                await self.listImages()
            }
        }
        .sheet(item: $createContainerForImage, onDismiss: {
            Task {
                await self.listImages()
            }
        }, content: { image in
            CreateContainerView(imageReference: image.imageDescription.reference)
        })
        .sheet(item: $showInUseContainerForImage, content: { image in
            ImageContainersView(image: image)
        })
        .sheet(item: $showImageDetails, content: { image in
            ImageDetailView(
                image: image,
                createContainer: {
                    self.createContainerForImage = image
                },
                showSaveImage: $showSaveImage,
                showDeleteConfirmation: $showDeleteConfirmation
            )
        })
        .sheet(isPresented: $showSaveImage, onDismiss: {
            self.imagesToSave = ""
        }, content: {
            SaveImageView(images: self.images.map(\.imageDescription), imageReferences: $imagesToSave)
        })
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        })
        .confirmationDialog(
            "Delete Image?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let image = imageToDelete else {
                    return
                }
                
                Task {
                    do {
                        try await imageManager.delete(images: [image.imageDescription])
                        
                        await self.listImages()
                    } catch (let err) {
                        self.error = err
                        self.showError = true
                    }
                }
                
                imageToDelete = nil
            }
            
            Button("Cancel", role: .cancel) {
                imageToDelete = nil
            }
        } message: {
            if let image = imageToDelete {
                Text("Delete \(image.name):\(image.tag)? This cannot be undone.")
            }
        }
    }
    
    func listImages() async {
        do {
            let images = try await imageManager.list(platform: .current)
            
            self.images = images
                .map(ImageViewModel.init)
                .sorted { ($0.name, $0.tag) < ($1.name, $1.tag) }
            self.lastUpdated = Date()
            
        } catch(let err) {
            self.error = err
            self.showError = true
        }
    }
}

#Preview {
    ImagesView(
        searchText: .constant(""),
        refreshTrigger: 0
    )
    .environment(ContainerManager())
}
