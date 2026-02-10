//
//  ImagesView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import SwiftUI
import ContainerSystem
import ContainerResource

struct ImagesView: View {
    @Environment(ContainerManager.self) private var containerManager
    @Environment(ImageManager.self) private var imageManager
    @Environment(SystemManager.self) private var system

    @Binding var searchText: String

    var onRefresh: (() async -> Void)? = nil

    @State private var images: [ImageViewModel] = []
    @State private var lastUpdated: Date? = nil
    @State private var createContainerForImage: ImageViewModel? = nil
    @State private var imagesToSave: String =  ""
    @State private var imageToDelete: ImageViewModel?
    @State private var error: Error?
    @State private var showError: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var showInUseContainerForImage: ImageViewModel?
    @State private var showSaveImageView: Bool = false

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
            Table(of: ImageViewModel.self, columns: {
                TableColumn("Name") { image in
                    
                    Text(image.name)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(height: 48)
                }
                .width(min: 80, ideal: 80)
                
                TableColumn("Tag") { image in
                    Text(image.tag)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 64)

                TableColumn("Digest") { image in
                    Text(image.formattedDigest)
                        .lineLimit(1)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .width(min: 100, ideal: 140, max: 180)

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
                        } else {
                            Text("Unused")
                        }
                    }
                    .lineLimit(1)

                }
                .width(64)

                TableColumn("OS") { image in
                    Text(image.formattedOS)
                }
                .width(min: 36, ideal: 36, max: 72)

                TableColumn("Arch") { image in
                    Text(image.formattedArch)
                }
                .width(min: 48, ideal: 48, max: 72)

                
                TableColumn("Variant") { image in
                    Text(image.variant)
                }
                .width(64)
                
                TableColumn("Size") { image in
                    Text(image.formattedSize)
                }
                .width(64)
                
                TableColumn("Created") { image in
                    Text(image.formattedCreated)
                }
                .width(min: 64, ideal: 64, max: 200)

                TableColumn("Actions") { image in

                    HStack(spacing: 12) {
                        
                        Button(action: {
                            self.createContainerForImage = image
                        }, label: {
                            Image(systemName: "cube.fill")
                                .foregroundStyle(.blue)
                        })
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            self.imagesToSave = image.imageDescription.reference
                            self.showSaveImageView = true
                        }, label: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                        })
                        .buttonStyle(.plain)

                        Button(action: {
                            imageToDelete = image
                            showDeleteConfirmation = true
                        }, label: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(image.inUse ? .secondary : Color.red)
                        })
                        .disabled(image.inUse)
                        .buttonStyle(.plain)

                    }
                    .padding(.horizontal, 8)
                }
                .width(128)
                

            }, rows: {
                ForEach(filteredImages)
            })
            .tableStyle(.automatic)
            .alternatingRowBackgrounds(.disabled)
            .overlay(alignment: .center, content: {
                if !self.system.isRunning {
                    ContainerSystemView()
                } else if filteredImages.isEmpty {
                    ContentUnavailableView(
                        trimmedText.isEmpty ? "No Images Found" : "No Matching Images",
                        systemImage: NavigationTab.images.icon
                    )
                }
            })
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
        .sheet(item: $createContainerForImage, onDismiss: {
            Task {
                await self.listImages()
            }
        }, content: { image in
            CreateContainerView(imageReference: image.imageDescription.reference)
        })
        .sheet(item: $showInUseContainerForImage, onDismiss: {
            Task {
                await self.listImages()
            }
        }, content: { image in
        
            RunningContainersView(containers: image.inUseContainers.map({ContainerViewModel($0)}), updateContainer: { id in
                let container = try await containerManager.get(id: id)
                
                guard let index = self.showInUseContainerForImage?.inUseContainers.firstIndex(where: {$0.configuration.id == id }) else {
                    return
                }

                self.showInUseContainerForImage?.inUseContainers[index] = container
            }, deleteContainer: { id in
                self.showInUseContainerForImage?.inUseContainers.removeAll(where: {$0.configuration.id == id})
            })
        })
        .sheet(isPresented: $showSaveImageView, onDismiss: {
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
            let containers = try await containerManager.list()
            let images = try await imageManager.list()

            // Create display models from ImageDescription
            let displayModels = images.map { ImageViewModel($0, containers: containers) }

            self.images = displayModels
            self.lastUpdated = Date()

        } catch(let err) {
            self.error = err
            self.showError = true
        }
    }
}

#Preview {
    ImagesView(
        searchText: .constant("")
    )
}
