//
//  ImageContainersView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem
import ContainerizationError
import ContainerResource

struct ImageContainersView: View {
    var containers: [ContainerViewModel]

    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Containers Using This Image")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(containers.count) \(containers.count == 1 ? "container" : "containers")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Table
            if containers.isEmpty {
                ContentUnavailableView {
                    Label("No Containers", systemImage: "cube.fill")
                } description: {
                    Text("No containers are currently using this image")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(of: ContainerViewModel.self, columns: {
                    TableColumn("Name") { container in
                        HStack(spacing: 8) {
                            // Status indicator
                            Circle()
                                .fill(container.status == .running ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            
                            Text(container.id)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .frame(height: 40)
                    }
                    .width(min: 120, ideal: 180, max: 300)
                    
                    TableColumn("Image") { container in
                        Text(container.imageName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 160, max: 250)
                    
                    TableColumn("State") { container in
                        HStack(spacing: 4) {
                            Text(container.formattedState)
                                .font(.subheadline)
                                .foregroundStyle(container.status == .running ? .primary : .secondary)
                        }
                    }
                    .width(min: 64, ideal: 80, max: 100)
                    
                }, rows: {
                    ForEach(containers)
                })
                .tableStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
            }
            
            // Bottom bar
            Divider()
            
            HStack {
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}
