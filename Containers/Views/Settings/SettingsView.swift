//
//  SettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import AppKit
import SwiftUI
import ContainerSystem

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case network
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .general: "General"
        case .network: "Network"
        }
    }
    
    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .network: "network"
        }
    }
}

struct SettingsView: View {
    @Environment(NetworkManager.self) private var networkManager
    @Environment(SystemManager.self) private var system
    
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var storageLocation = UserDefaults.applicationDataRoot
    @State private var dnsDomains: [DNSDomainSetting] = []
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 18)
            
            content
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(selectedTab.title)
        .task {
            refreshSettings()
        }
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                showError = false
            }
        }, message: {
            Text(errorMessage ?? "Unknown Error")
        })
        .onChange(of: errorMessage) {
            if errorMessage != nil {
                showError = true
            }
        }
        .onChange(of: showError) {
            if !showError {
                errorMessage = nil
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:
            generalSettingsContent
        case .network:
            networkSettingsContent
        }
    }
    
    private var generalSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                storageLocationSection
            }
            .frame(maxWidth: 560, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var networkSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dnsDomainsSection
            }
            .frame(maxWidth: 560, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var storageLocationPath: Binding<String> {
        Binding(
            get: { storageLocation.path },
            set: { _ in }
        )
    }
    
    private var storageLocationSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsRow(label: "Storage:") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Storage location", text: storageLocationPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button(action: chooseStorageLocation) {
                            Image(systemName: "folder")
                        }
                        .help("Choose")
                        .disabled(system.isRunning)
                    }
                    
                    Text("Containers, images, volumes, kernels, and build data are stored in this folder. Changes take effect the next time the container system starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button("Use Default", action: resetStorageLocation)
                    .disabled(system.isRunning || UserDefaults.usesDefaultApplicationDataRoot)
            }
        }
    }
    
    private var dnsDomainsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsRow(label: "DNS Domains:") {
                VStack(alignment: .leading, spacing: 8) {
                    if dnsDomains.isEmpty {
                        Text("No domains configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dnsDomains) { domain in
                            Text(domain.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    
                    Text("DNS domains let containers access host services, such as host.containers.internal:8000.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            SettingsWarning("DNS domain management requires administrator privileges. Manage domains by creating resolver files in /etc/resolver/.")
        }
    }
    
    private func refreshSettings() {
        storageLocation = UserDefaults.applicationDataRoot
        dnsDomains = networkManager.listDomains().map(DNSDomainSetting.init(name:))
    }
    
    private func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = storageLocation
        panel.prompt = "Choose"
        panel.message = "Choose where Containers stores containers, images, volumes, kernels, and build data."
        
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            UserDefaults.setApplicationDataRoot(url, bookmarkData: bookmarkData)
            storageLocation = UserDefaults.applicationDataRoot
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func resetStorageLocation() {
        UserDefaults.resetApplicationDataRoot()
        storageLocation = UserDefaults.applicationDataRoot
    }
}

private struct DNSDomainSetting: Identifiable {
    let id = UUID()
    var name: String
}

private struct SettingsWarning: View {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SettingsView()
        .environment(NetworkManager())
        .environment(SystemManager())
}
