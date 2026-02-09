//
//  SettingsView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/02/08.
//

import SwiftUI
import ContainerSystem
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(DNSManager.self) private var dnsManager
    
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var startSystemTimeoutSeconds = UserDefaults.startSystemTimeoutSeconds
    @State private var stopContainerTimeoutSeconds = UserDefaults.stopContainerTimeoutSeconds
    @State private var shutdownSystemTimeoutSeconds = UserDefaults.shutdownSystemTimeoutSeconds
    @State private var dnsDomains: [String] = []
    @State private var newDNSDomain: String = ""
        
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Configure application preferences")
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
                    // Timeout Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text("Timeout Configuration")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundStyle(.blue)
                        }
                        
                        Divider()
                        
                        // Start System
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start System")
                                    .font(.body)
                                Text("Timeout for starting the container system")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                TextField("", value: $startSystemTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                
                                Text("sec")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        Divider()
                        
                        // Stop System
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stop System")
                                    .font(.body)
                                Text("Timeout for shutting down the container system")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            
                            HStack(spacing: 4) {
                                TextField("", value: $shutdownSystemTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)

                                Text("sec")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)

                        Divider()
                        
                        // Stop Container
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stop Container")
                                    .font(.body)
                                Text("Timeout for stopping individual containers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()

                            HStack(spacing: 4) {
                                TextField("", value: $stopContainerTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)

                                Text("sec")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // DNS Domains
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text("DNS Domains")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "network")
                                .foregroundStyle(.blue)
                        }
                        
                        Text("DNS domains let containers access host services. Inside a container, reach the host via the domain name (e.g., host.containers.internal:8000). Admin password will be prompted for changes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Divider()

                        if dnsDomains.isEmpty {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("No domains configured.")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(dnsDomains, id: \.self) { domain in
                                    HStack {
                                        HStack(spacing: 8) {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 6))
                                                .foregroundStyle(.blue)
                                            
                                            Text(domain)
                                                .font(.system(.body, design: .monospaced))
                                        }

                                        Spacer()

                                        Button(action: {
                                            deleteDomain(domain)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete domain")
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        Divider()

                        HStack(spacing: 8) {
                            TextField("Domain name (e.g., host.containers.internal)", text: $newDNSDomain)
                                .textFieldStyle(.roundedBorder)

                            Button("Add Domain") {
                                createDomain()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newDNSDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
        }
        .task {
            self.dnsDomains = dnsManager.listDomains()
        }
        .alert("Error", isPresented: $showError, actions: {
            Button("OK") {
                self.showError = false
            }
        }, message: {
            Text(self.errorMessage ?? "Unknown Error")
        })
        .onChange(of: self.errorMessage) {
            if errorMessage != nil {
                self.showError = true
            }
        }
        .onChange(of: self.showError) {
            if !showError {
                self.errorMessage = nil
            }
        }
        .onChange(of: startSystemTimeoutSeconds) {
            UserDefaults.startSystemTimeoutSeconds = startSystemTimeoutSeconds
        }
        .onChange(of: stopContainerTimeoutSeconds) {
            UserDefaults.stopContainerTimeoutSeconds = stopContainerTimeoutSeconds
        }
        .onChange(of: shutdownSystemTimeoutSeconds) {
            UserDefaults.shutdownSystemTimeoutSeconds = shutdownSystemTimeoutSeconds
        }
    }
    
    private func createDomain() {
        do {
            try dnsManager.createDomain(name: newDNSDomain)
            self.newDNSDomain = ""
            self.dnsDomains = dnsManager.listDomains()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func deleteDomain(_ domain: String) {
        do {
            try dnsManager.deleteDomain(name: domain)
            self.dnsDomains = dnsManager.listDomains()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func openFile(_ url: URL) {
        let result = NSWorkspace.shared.selectFile(
            url.absoluteString,
            inFileViewerRootedAtPath: url.parent.absoluteString
        )
        if !result {
            self.errorMessage = "Failed to open the File."
        }
    }

}

#Preview {
    SettingsView()
}
