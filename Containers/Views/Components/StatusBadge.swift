//
//  StatusBadge.swift
//  Containers
//
//  Created by Axel Martinez on 31/05/2026.
//

import ContainerSystem
import SwiftUI

struct StatusBadge: View {
    let status: RuntimeStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(status.rawValue.localizedCapitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    (status == .running ? Color.green : Color.red)
                        .opacity(0.1)
                )
        )
    }

    private var statusColor: Color {
        switch status {
        case .running:
            return Color(.green)
        case .stopping:
            return Color(.orange)
        case .stopped:
            return Color(.red)
        case .unknown:
            return Color(.black)
        }
    }
}
