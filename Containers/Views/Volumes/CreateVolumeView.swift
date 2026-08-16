//
//  CreateVolumeView.swift
//  Containers
//
//  Created by Axel Martinez on 2025/11/03.
//

import ContainerSystem
import ContainerizationOCI
import SwiftUI

struct CreateVolumeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info"
        case options = "Options"

        var id: String { rawValue }
    }

    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismiss) private var dismiss

    @SwiftUI.State private var name: String = ""
    @SwiftUI.State private var options: [KeyValue] = []
    @SwiftUI.State private var labels: [KeyValue] = []
    @SwiftUI.State private var sizeValue: Double = 512
    @SwiftUI.State private var sizeUnit: UnitInformationStorage = .gigabytes
    @SwiftUI.State private var errorMessage: String?
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var selectedTab: Tab = .info

    var body: some View {
        CreateView(
            title: "Create New Volume",
            errorMessage: $errorMessage,
            isProcessing: showProgressView,
            progressTitle: "Creating volume...",
            width: 550,
            height: 450,
            scrollsContent: true,
            contentPadding: selectedTab == .info ? 20 : 0,
            tabBar: {
                CreateViewTabBar(selection: $selectedTab)
            },
            content: {
                tabContent
            },
            actions: {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Button {
                    createVolume()
                } label: {
                    Text("Create")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .defaultAction(
                    enabled: !name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        )
        .animation(.default, value: self.labels.count)
        .animation(.default, value: self.options.count)
        .onDisappear {
            self.showProgressView = false
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            infoTab
        case .options:
            optionsTab
        }
    }

    private var infoTab: some View {
        FormStack {
            FormRow(title: "Name") {
                FormField(placeholder: "Ex: volume-1", value: $name)
            }

            // The only row with two controls in one column, so it holds the
            // controls directly rather than going through FormField.
            FormRow(
                title: "Size",
                description:
                    "Sets the maximum capacity for the volume. Disk space is used as data is written, not reserved up front."
            ) {
                HStack {
                    TextField(
                        value: $sizeValue,
                        format: .number,
                        prompt: Text("Size")
                    ) {
                        EmptyView()
                    }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()

                    FormPicker(
                        placeholder: "Unit",
                        options: [.megabytes, .gigabytes, .terabytes],
                        selection: $sizeUnit,
                        fillsAvailableWidth: false
                    )
                }
            }
        }
    }

    private var optionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormList(
                items: $labels,
                title: "Labels",
                columnTitles: ["Key", "Value"],
                addLabel: "Add Label",
                emptyMessage: "No Labels",
                hasContentBelow: true,
                newItem: { KeyValue() },
                rowFields: { keyValue in
                    [
                        .init(
                            placeholder: "Key",
                            text: keyValue.key,
                            isMonospaced: true
                        ),
                        .init(
                            placeholder: "Value",
                            text: keyValue.value,
                            isMonospaced: true
                        ),
                    ]
                }
            )
            .padding(.horizontal)

            FormList(
                items: $options,
                title: "Driver Specific Options",
                columnTitles: ["Key", "Value"],
                addLabel: "Add Option",
                emptyMessage: "No Options",
                newItem: { KeyValue() },
                rowFields: { keyValue in
                    [
                        .init(
                            placeholder: "Key",
                            text: keyValue.key,
                            isMonospaced: true
                        ),
                        .init(
                            placeholder: "Value",
                            text: keyValue.value,
                            isMonospaced: true
                        ),
                    ]
                }
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValueSummary(_ keyValue: KeyValue) -> String {
        let key = keyValue.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = keyValue.value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

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
        let trimmedName = self.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty else {
            self.errorMessage = "Name is not specified."
            return
        }

        Task {
            self.showProgressView = true
            self.errorMessage = nil

            do {
                let validLabels = self.labels.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && !$0.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                })
                let validOptions = self.options.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && !$0.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                })

                // Convert to bytes for API
                let sizeInBytes: UInt64? =
                    sizeValue > 0
                    ? UInt64(
                        Measurement(
                            value: sizeValue,
                            unit: sizeUnit
                        ).converted(to: .bytes).value
                    ) : nil

                try await volumeManager.create(
                    name: trimmedName,
                    labels: validLabels,
                    options: validOptions,
                    sizeInBytes: sizeInBytes
                )

                dismiss()
            } catch (let error) {
                self.errorMessage = "\(error)"
            }

            self.showProgressView = false
        }
    }
}
