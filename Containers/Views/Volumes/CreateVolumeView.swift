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
    @Environment(\.close) private var close
    
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
                    
                    EditableField(
                        title: "Name",
                        placeholder: "Ex: volume-1",
                        value: $name
                    )
                   
                    // Volume Size
                    
                    EditableField(
                        title: "Size",
                        placeholder: "Size",
                        value: $sizeValue,
                        format: .number,
                        fieldWidth: 200,
                        options: [.megabytes, .gigabytes, .terabytes],
                        selection: $sizeUnit
                    )
                    
                    // Labels
                    
                    EditableList(
                        items: $labels,
                        title: "Metadata",
                        columnTitles: ["Key", "Value"],
                        addLabel: "Add Label",
                        newItem: { KeyValue() },
                        rowSummary: keyValueSummary,
                        rowValues: { [$0.key, $0.value] },
                        editorContent: { $keyValue in
                            KeyValueEditor(keyValue: $keyValue)
                        }
                    )
                    
                    // Options
                    
                    EditableList(
                        items: $options,
                        title: "Driver Specific Options",
                        columnTitles: ["Key", "Value"],
                        addLabel: "Add Option",
                        newItem: { KeyValue() },
                        rowSummary: keyValueSummary,
                        rowValues: { [$0.key, $0.value] },
                        editorContent: { $keyValue in
                            KeyValueEditor(keyValue: $keyValue)
                        }
                    )
                }
                .padding(20)
            
            
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
                    close()
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
        .frame(width: 550, height: 550)
        .animation(.default, value: self.labels.count)
        .animation(.default, value: self.options.count)
        .animation(.default, value: showAdditionalSettings)
        .onDisappear {
            self.showProgressView = false
        }
    }
    
    private func keyValueSummary(_ keyValue: KeyValue) -> String {
        let key = keyValue.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = keyValue.value.trimmingCharacters(in: .whitespacesAndNewlines)

        if key.isEmpty && value.isEmpty {
            return "New Item"
        }

        if value.isEmpty {
            return key
        }

        if key.isEmpty {
            return value
        }

        return "\(key)=\(value)"
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
                
                close()
            } catch (let error) {
                self.errorMessage = "\(error)"
            }
            
            self.showProgressView = false
        }
    }
}
