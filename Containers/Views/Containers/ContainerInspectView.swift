//
//  ContainerInspectView.swift
//  Containers
//
//  Created by Axel Martinez on 10/2/26.
//

import SwiftUI
import AppKit
import ContainerSystem
import ContainerResource

struct ContainerInspectView : View {
    let container: ContainerViewModel
    
    var body : some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20,
                content: {
                    let environments = KeyValue.fromEnvironment(container.snapshot)
                    let ports = KeyValue.fromPorts(container.snapshot)
                    
                    // Environment Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(
                            title: "Environment Variables",
                            subtitle: nil
                        )
                        
                        if environments.isEmpty {
                            emptyStateView(text: "No environment variables")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(environments) { env in
                                    HStack {
                                        Text(env.key)
                                            .font(
                                                .system(
                                                    .body,
                                                    design: .monospaced
                                                )
                                            )
                                            .foregroundStyle(.primary)
                                            .frame(
                                                alignment: .leading
                                            )
                                        
                                        Text("=")
                                            .foregroundStyle(.secondary)
                                        
                                        Text(env.value)
                                            .font(
                                                .system(
                                                    .body,
                                                    design: .monospaced
                                                )
                                            )
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(
                                                maxWidth: .infinity,
                                                alignment: .leading
                                            )
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Color(nsColor: .controlBackgroundColor)
                                    )
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Ports Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Port Mappings", subtitle: nil)
                        
                        if ports.isEmpty {
                            emptyStateView(text: "No port mappings")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(ports) { port in
                                    HStack {
                                        Label(port.key, systemImage: "network")
                                            .font(
                                                .system(
                                                    .body,
                                                    design: .monospaced
                                                )
                                            )
                                            .foregroundStyle(.primary)
                                            .frame(
                                                alignment: .leading
                                            )
                                        
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        
                                        Text(port.value)
                                            .font(
                                                .system(
                                                    .body,
                                                    design: .monospaced
                                                )
                                            )
                                            .foregroundStyle(.secondary)
                                            .frame(
                                                maxWidth: .infinity,
                                                alignment: .leading
                                            )
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Color(nsColor: .controlBackgroundColor)
                                    )
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Volumes Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(title: "Volumes", subtitle: nil)
                        
                        let volumeFSs = container.snapshot.volumeFSs
                        
                        if volumeFSs.isEmpty {
                            emptyStateView(text: "No volumes mounted")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(volumeFSs.enumerated()), id: \.offset) { _, fileSystem in
                                    if let name = fileSystem.volumeName {
                                        HStack {
                                            Label(
                                                name,
                                                systemImage: "internaldrive"
                                            )
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(
                                                alignment: .leading
                                            )
                                            
                                            let fileURL = URL(
                                                filePath: fileSystem.source
                                            )
                                            
                                            HStack(spacing: 8) {
                                                Text(
                                                    "\(fileSystem.source) → \(fileSystem.destination)"
                                                )
                                                .font(
                                                    .system(
                                                        .body,
                                                        design: .monospaced
                                                    )
                                                )
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(
                                                    maxWidth: .infinity,
                                                    alignment: .leading
                                                )
                                                
                                                Button {
                                                    self.openFile(fileURL)
                                                } label: {
                                                    Image(
                                                        systemName:
                                                            "arrow.up.forward.square"
                                                    )
                                                    .font(.body)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Open in Finder")
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Color(
                                                nsColor: .controlBackgroundColor
                                            )
                                        )
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }
            )
            .padding(20)
        }
    }
    
    private func sectionHeader(title: String, subtitle: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func emptyStateView(text: String) -> some View {
        HStack {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func openFile(_ url: URL) {
        let _ = NSWorkspace.shared.selectFile(
            url.absoluteString,
            inFileViewerRootedAtPath: url.parent.absoluteString
        )
    }
}
