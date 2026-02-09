//
//  VolumeSelectionView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerizationOCI
import ContainerResource

struct VolumeSelectionView: View {
    var volumes: [Volume]
    var onVolumeSelect: (String) -> Void
    
    @SwiftUI.State private var searchText: String = ""
    @SwiftUI.State private var selectedVolume: Volume?
    
    @Environment(\.dismiss) private var dismiss

    private var trimmedText: String {
        self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var filteredVolumes: [Volume] {
        if trimmedText.isEmpty {
            return volumes
        }
        return volumes.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Volume")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(filteredVolumes.count) \(filteredVolumes.count == 1 ? "volume" : "volumes") available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search volumes...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Content
            if filteredVolumes.isEmpty {
                ContentUnavailableView {
                    Label("No Volumes Found", systemImage: "internaldrive")
                } description: {
                    if !trimmedText.isEmpty {
                        Text("No volumes match '\(trimmedText)'")
                    } else {
                        Text("No volumes available")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredVolumes, id: \.id) { volume in
                            VolumeSelectionRow(
                                volume: volume,
                                isSelected: selectedVolume?.id == volume.id,
                                onSelect: {
                                    selectedVolume = volume
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
            }
            
            Divider()
            
            // Bottom Bar
            HStack {
                Spacer()
                
                Button("Cancel") {
                    self.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Select") {
                    if let volume = selectedVolume {
                        self.onVolumeSelect(volume.name)
                        self.dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedVolume == nil)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 500)
    }
}

struct VolumeSelectionRow: View {
    let volume: Volume
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "internaldrive")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    )
                
                // Volume info
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)
                    
                    Text(volume.driver)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
