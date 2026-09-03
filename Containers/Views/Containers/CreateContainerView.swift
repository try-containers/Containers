//
//  CreateContainerView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/05.
//

import ContainerSystem
import Containerization
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import SwiftUI
import Virtualization

struct CreateContainerView: View {
    enum Mode {
        case create
        case run

        var title: String {
            switch self {
            case .create:
                "Create New Container"
            case .run:
                "Run Container"
            }
        }

        var progressTitle: String {
            switch self {
            case .create:
                "Creating container..."
            case .run:
                "Running container..."
            }
        }

        var buttonTitle: String {
            switch self {
            case .create:
                "Create"
            case .run:
                "Run"
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info"
        case process = "Process"
        case options = "Options"

        var id: String { rawValue }
    }

    @Environment(ContainerManager.self) private var containerManager
    @Environment(ImageManager.self) private var imageManager
    @Environment(VolumeManager.self) private var volumeManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @SwiftUI.State var imageReference: String

    @SwiftUI.State private var process: ContainerProcess = .init()
    @SwiftUI.State private var container: ContainerInfo = .init()
    @SwiftUI.State private var volumes: [VolumeMount] = []
    @SwiftUI.State private var mounts: [Mount] = []
    @SwiftUI.State private var ports: [PortMapping] = []
    @SwiftUI.State private var environments: [KeyValue] = []
    @SwiftUI.State private var resource: ContainerConfiguration.Resources = .init()
    @SwiftUI.State private var registryScheme: String = RequestScheme.auto.rawValue
    @SwiftUI.State private var platformString: String = Platform.current.description
    @SwiftUI.State private var shmSize: String = ""
    @SwiftUI.State private var capabilities: [Capability] = []
    @SwiftUI.State private var errorAlert: ErrorAlert?
    @SwiftUI.State private var localImages: [ImageDescription] = []
    @SwiftUI.State private var availableVolumes: [Volume] = []
    @SwiftUI.State private var showProgressView: Bool = false
    @SwiftUI.State private var creationTask: Task<Void, Never>?
    @SwiftUI.State private var stepTransitionDirection: Int = 1
    @SwiftUI.State private var showStopConfirmation: Bool = false
    @SwiftUI.State private var showPickLocalImage: Bool = false
    @SwiftUI.State private var selectedTab: Tab = .info

    init(imageReference: String, mode: Mode = .create) {
        self.mode = mode
        self._imageReference = State(initialValue: imageReference)
    }

    var body: some View {
        CreateView(
            title: mode.title,
            error: $errorAlert,
            isProcessing: showProgressView,
            progressTitle: containerManager.progress.description.isEmpty
                ? mode.progressTitle : containerManager.progress.description,
            width: Self.sheetWidth,
            height: 460,
            scrollsContent: selectedTab == .options,
            contentPadding: selectedTab == .info ? 20 : 0,
            contentID: showProgressView
                ? AnyHashable("progress") : AnyHashable(selectedTab),
            contentTransition: stepTransition,
            tabBar: {
                CreateViewTabBar(selection: $selectedTab)
            },
            content: {
                tabContent
            },
            actions: {
                Spacer()
                Button {
                    confirmStop()
                } label: {
                    Text("Cancel")
                        .frame(width: .sheetButtonLabelWidth)
                }
                .buttonStyle(.bordered)

                Button {
                    createContainer()
                } label: {
                    Text(mode.buttonTitle)
                        .frame(width: .sheetButtonLabelWidth)
                }
                .defaultAction(
                    enabled: !showProgressView
                        && !imageReference.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            },
            progress: {
                if !containerManager.progress.detail.isEmpty {
                    Text(containerManager.progress.detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        )
        .sheet(
            isPresented: $showPickLocalImage,
            content: {
                ItemPicker(
                    title: "Choose Image",
                    actionTitle: "Choose",
                    items: self.localImages.map {
                        Item(id: $0.digest, label: $0.reference)
                    },
                    onSelect: { self.imageReference = $0.label }
                )
            }
        )
        .confirmationDialog(
            mode == .run ? "Stop Running Container" : "Stop Creating Container",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                cancelCreation()
                dismiss()
            }

            Button("Continue", role: .cancel) {}
        } message: {
            Text(
                "The container hasn’t finished being \(mode == .run ? "started" : "created"). Stopping now discards it."
            )
        }
        .task {
            await preloadLocalImages()
            await preloadVolumes()
        }
        .onDisappear {
            self.showProgressView = false
        }
    }

    /// Work under way is only stopped on purpose, so the button asks first.
    private func confirmStop() {
        guard showProgressView else {
            dismiss()
            return
        }

        showStopConfirmation = true
    }

    private static var platformOptions: [String] {
        let current = Platform.current
        var options = [current.description]

        if current.architecture == "arm64" {
            options.append("linux/amd64")
        }

        return options
    }

    @ViewBuilder
    private var imageSelectionField: some View {
        if mode == .run {
            FormRow(title: "Image") {
                Text(imageReference)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            FormRow(title: "Image") {
                FormPicker(
                    placeholder: "Select Image...",
                    options: localImages.map { $0.reference },
                    selection: $imageReference,
                    actionTitle: "Other...",
                    onAction: { showPickLocalImage = true }
                )
            }
        }
    }

    private func preloadLocalImages() async {
        guard localImages.isEmpty else { return }

        localImages = (try? await imageManager.list().map(\.description)) ?? []

        if imageReference.isEmpty, let first = localImages.first {
            imageReference = first.reference
        }
    }

    private func showLocalImageSelection() {
        guard localImages.isEmpty else {
            showPickLocalImage = true
            return
        }

        Task {
            do {
                showProgressView = true
                localImages = try await imageManager.list().map(\.description)
                showProgressView = false
                showPickLocalImage = true
            } catch (let error) {
                showProgressView = false
                errorAlert = ErrorAlert(
                    "The images couldn’t be loaded.",
                    error: error
                )
            }
        }
    }

    /// Nested virtualization is refused outright by the Virtualization
    /// framework on hardware that cannot do it, so the flag is not offered
    /// where ticking it could only fail.
    private static let supportsNestedVirtualization =
        VZGenericPlatformConfiguration.isNestedVirtualizationSupported

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .info:
            infoTab
        case .process:
            processTab
        case .options:
            optionsTab
        }
    }

    private var infoTab: some View {
        FormStack {
            imageSelectionField

            FormRow(
                title: "Name",
                description:
                    "Leave empty to generate a unique name automatically. Names start with a letter or number, and may contain only letters, numbers, underscores, periods, and hyphens."
            ) {
                FormField(
                    placeholder: "my-container",
                    value: $container.name,
                    filter: EntityName.valid(from:)
                )
            }
        }
    }

    private var processTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormStack {
                FormRow(
                    title: "Entrypoint",
                    description: "Override the entrypoint of the image."
                ) {
                    FormField(
                        placeholder: "/bin/sh -c \"echo hello\"",
                        value: Binding(
                            get: { container.entryPoint ?? "" },
                            set: {
                                container.entryPoint = $0.isEmpty ? nil : $0
                            }
                        )
                    )
                }

                FormRow(title: "Stop Signal") {
                    FormField(
                        placeholder: "SIGTERM",
                        value: Binding(
                            get: { container.stopSignal ?? "" },
                            set: {
                                container.stopSignal =
                                    $0.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty ? nil : $0
                            }
                        )
                    )
                }
            }
            .padding(20)

            Divider()

            FormList(
                items: $environments,
                columnTitles: ["Environment Variables", "Value"],
                addLabel: "Add Environment Variable",
                emptyMessage: "No Environment Variables",
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
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var optionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormStack {
                FormRow(
                    title: "Platform",
                    description:
                        "Choose the image variant to run. AMD64 containers use Rosetta on Apple Silicon."
                ) {
                    FormPicker(
                        placeholder: "Platform",
                        options: Self.platformOptions,
                        selection: $platformString
                    )
                }

                FormRow(
                    title: "Shared Memory",
                    description: "Size of /dev/shm (e.g. 64M, 1G)"
                ) {
                    FormField(
                        placeholder: "64M",
                        value: $shmSize
                    )
                }

                FormRow(title: "Management") {
                    VStack(alignment: .leading) {
                        Toggle(
                            "Run detached from the process",
                            isOn: $container.detach
                        )

                        Toggle(
                            "Remove the container after it stops",
                            isOn: $container.deleteOnTermination
                        )

                        Toggle(
                            "Mount the root filesystem as read-only",
                            isOn: $container.readOnly
                        )

                        Toggle(isOn: $container.virtualization) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "Expose virtualization capabilities to the container"
                                )

                                Text(
                                    Self.supportsNestedVirtualization
                                        ? "Requires host and guest support."
                                        : "Nested virtualization needs an Apple silicon M3 chip or later."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!Self.supportsNestedVirtualization)

                        Toggle(
                            "Forward SSH agent socket to container",
                            isOn: $container.ssh
                        )
                    }
                    .toggleStyle(.checkbox)
                    .fieldProse()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            FormList(
                items: $volumes,
                title: "Volumes",
                editorDescription:
                    "Select an existing volume or create an anonymous volume. To create a new named volume, use the Volumes section.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Volume",
                emptyMessage: "No Volumes",
                hasContentBelow: true,
                newItem: {
                    VolumeMount(
                        source: availableVolumes.isEmpty
                            ? .anonymousVolume : .volume,
                        volumeName: availableVolumes.last?.name ?? ""
                    )
                },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: { !$0.trimmedTarget.isEmpty },
                editorContent: { $volume in
                    VolumeEditor(
                        mount: $volume,
                        availableVolumes: availableVolumes
                    )
                }
            )
            .padding(.horizontal)

            FormList(
                items: $mounts,
                title: "Mounts",
                editorDescription:
                    "Share a host path with the container, or tick Temporary mount to create an in-memory mount instead.",
                columnTitles: ["Source", "Target"],
                addLabel: "Add Mount",
                emptyMessage: "No Mounts",
                hasContentBelow: true,
                newItem: { Mount() },
                rowSummary: \.summary,
                rowValues: \.columns,
                canSave: {
                    !$0.trimmedTarget.isEmpty
                        && ($0.isTemporary || $0.hostURL != nil)
                },
                editorContent: { $mount in
                    MountEditor(mount: $mount)
                }
            )
            .padding(.horizontal)

            FormList(
                items: $ports,
                title: "Port Mappings",
                editorDescription:
                    "Publish a container port on the host, so it can be reached from outside the container.",
                columnTitles: ["Host", "Container", "Protocol"],
                addLabel: "Add Port Mapping",
                emptyMessage: "No Port Mappings",
                hasContentBelow: true,
                newItem: { PortMapping() },
                rowSummary: \.summary,
                rowValues: \.columns,
                editorContent: { $port in
                    PortEditor(port: $port)
                }
            )
            .padding(.horizontal)

            FormList(
                items: $capabilities,
                title: "Capabilities",
                columnTitles: ["Capability"],
                addLabel: "Add Capability",
                emptyMessage: "No Capabilities",
                newItem: { Capability() },
                rowFields: { $capability in
                    [
                        .init(
                            placeholder: "CAP_NET_ADMIN",
                            text: $capability.name
                        )
                    ]
                }
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preloadVolumes() async {
        guard availableVolumes.isEmpty else { return }
        availableVolumes = (try? await volumeManager.list()) ?? []
    }

    private static let sheetWidth: CGFloat = 660
    private static let stepAnimation: Animation = .easeOut(duration: 0.2)

    private var stepTransition: AnyTransition {
        let distance = Self.sheetWidth / 3
        let shift = stepTransitionDirection > 0 ? distance : -distance

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: shift)),
            removal: .identity
        )
    }

    /// Stops work still in flight, so that closing the sheet leaves nothing
    /// running behind it.
    private func cancelCreation() {
        guard showProgressView else { return }

        creationTask?.cancel()
        creationTask = nil
        showProgressView = false
        containerManager.progress.finish()
    }

    private func createContainer() {
        let trimmedReference = imageReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedReference.isEmpty else {
            self.errorAlert = ErrorAlert(
                "The container needs an image.",
                message: "Choose the image to create the container from."
            )
            return
        }

        let trimmedShmSize = shmSize.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var shmSizeInBytes: UInt64?

        if !trimmedShmSize.isEmpty {
            guard let bytes = try? Parser.memoryInBytes(from: trimmedShmSize)
            else {
                self.errorAlert = ErrorAlert(
                    "The shared memory size isn’t valid.",
                    message: "Enter a size such as 64M or 1G."
                )
                return
            }

            shmSizeInBytes = bytes
        }

        stepTransitionDirection = 1

        withAnimation(Self.stepAnimation) {
            self.showProgressView = true
        }

        creationTask = Task {
            containerManager.progress.begin(totalTasks: mode == .run ? 7 : 6)

            defer {
                containerManager.progress.finish()
            }

            do {
                let resolved = try await ResolvedMounts(
                    mounts: self.mounts,
                    volumes: self.volumes,
                    using: volumeManager
                )

                self.container.mounts = resolved.mounts
                self.container.platform = try Platform(
                    from: self.platformString
                )
                self.container.shmSize = shmSizeInBytes
                self.container.capabilities = self.capabilities.names

                self.container.publishPorts = self.ports.compactMap(
                    \.publishedPort
                )

                let validEnvironments = self.environments.filter({
                    !$0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        && !$0.value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                })

                self.process.environments = validEnvironments.map { kv in
                    "\(kv.key)=\(kv.value)"
                }

                // Make copies for actor boundary crossing
                let process = self.process
                let container = self.container
                let resource = self.resource
                let registryScheme = self.registryScheme

                let containerID = try await containerManager.create(
                    imageReference: trimmedReference,
                    imagesDir: UserDefaults.applicationDataRoot
                        .appendingPathComponent("images"),
                    arguments: [],
                    process: process,
                    container: container,
                    resource: resource,
                    registryScheme: registryScheme
                )

                var exitCode: Int32?

                if mode == .run {
                    exitCode = try await containerManager.run(
                        id: containerID,
                        detach: container.detach
                    )
                }

                if let exitCode, exitCode != 0 {
                    self.errorAlert = ErrorAlert(
                        "The container exited with status \(exitCode).",
                        message:
                            "Check the container’s logs for what went wrong."
                    )
                } else {
                    dismiss()
                }

            } catch is CancellationError {
                // The sheet was closed on purpose; there is nothing to report.
            } catch (let error) {
                self.errorAlert = ErrorAlert(
                    mode == .run
                        ? "The container couldn’t be started."
                        : "The container couldn’t be created.",
                    error: error,
                    // What went wrong here reads in full, so there is nothing
                    // to keep folded away.
                    showsDetails: false
                )
            }

            self.stepTransitionDirection = -1

            withAnimation(Self.stepAnimation) {
                self.showProgressView = false
            }
        }
    }
}
