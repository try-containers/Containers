//
//  PortEditor.swift
//  Containers
//
//  Created by Axel Martinez on 03/08/2026.
//

import ContainerSystem
import SwiftUI

/// The editors the create sheet's lists open for one drafted item at a time.
struct PortEditor: View {
    @Binding var port: PortsConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Host Address", text: $port.hostAddress)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Host Port", value: $port.host, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField(
                    "Container Port",
                    value: $port.container,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
            }

            Picker("Protocol", selection: $port.publishProtocol) {
                Text("TCP").tag(PublishProtocol.tcp)
                Text("UDP").tag(PublishProtocol.udp)
            }
            .pickerStyle(.segmented)
        }
    }
}
