//
//  CreateVolumeView.swift
//  Containers
//
//  Created by Axel Martinez on 2025/11/03.
//

import SwiftUI
import ContainerSystem
import ContainerizationOCI

struct CreateVolumeView: View {
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var name: String = ""
    @SwiftUI.State private var options: [KeyValue] = []
    @SwiftUI.State private var labels: [KeyValue] = []
    @SwiftUI.State private var sizeValue: Double = 1
    @SwiftUI.State private var sizeUnit: UnitInformationStorage = .megabytes
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var showAdditionalSettings: Bool = false
    @SwiftUI.State private var showProgressView: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Volume")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Configure your new volume settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Error message
                    if let errorMessage = self.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Volume Name Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            Text("Volume Name")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "internaldrive")
                                .foregroundStyle(.blue)
                        }
                        
                        TextField("Ex: volume-1", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Optional Settings
                    DisclosureGroup(
                        isExpanded: $showAdditionalSettings,
                        content: {
                            VStack(alignment: .leading, spacing: 16) {
                                Divider()
                                
                                // Volume Size
                                VStack(alignment: .leading, spacing: 8) {
                                    Label {
                                        Text("Volume Size")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } icon: {
                                        Image(systemName: "archivebox")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }

                                    HStack {
                                        TextField("Size", value: $sizeValue, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 100)

                                        Picker("", selection: $sizeUnit) {
                                            Text("MB").tag(UnitInformationStorage.megabytes)
                                            Text("GB").tag(UnitInformationStorage.gigabytes)
                                            Text("TB").tag(UnitInformationStorage.terabytes)
                                        }
                                        .labelsHidden()
                                        .frame(width: 80)
                                        
                                        Spacer()
                                    }
                                }
                                
                                Divider()
                                
                                // Labels
                                KeyValuesEditView(keyValues: $labels, title: "Volume Metadata (Label)")
                                
                                Divider()
                                
                                // Options
                                KeyValuesEditView(keyValues: $options, title: "Driver Specific Options")
                            }
                            .padding(.top, 12)
                        },
                        label: {
                            Label {
                                Text("Optional Settings")
                                    .font(.headline)
                            } icon: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
            
            Divider()
            
            // Bottom Bar
            HStack {
                if showProgressView {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                    Text("Creating volume...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    self.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Create Volume") {
                    createVolume()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
        .animation(.default, value: self.labels.count)
        .animation(.default, value: self.options.count)
        .animation(.default, value: showAdditionalSettings)
        .onDisappear {
            self.showProgressView = false
        }
    }
    
    private func createVolume() {
        let trimmedName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            self.errorMessage = "Name is not specified."
            return
        }

        Task {
            self.showProgressView = true
            self.errorMessage = nil
            
            do {
                let validLabels = self.labels.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
                let validOptions = self.options.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })

                // Convert to bytes for API
                let sizeInBytes: UInt64? = sizeValue > 0 ? UInt64(Measurement(
                    value: sizeValue,
                    unit: sizeUnit
                ).converted(to: .bytes).value) : nil

                try await volumeManager.create(
                    name: trimmedName,
                    labels: validLabels,
                    options: validOptions,
                    sizeInBytes: sizeInBytes
                )

                self.dismiss()
            } catch (let error) {
                self.errorMessage = "\(error)"
            }
            
            self.showProgressView = false
        }
    }
}
