//
//  ConnectionRowView.swift
//  DB+
//

import SwiftUI

struct ConnectionRowView: View {
    let profile: ConnectionProfile
    let isActive: Bool
    let isConnected: Bool
    var onConnect: () -> Void = {}
    var onTest: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: profile.mode.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayLabel)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onConnect() }
        .contextMenu {
            Button("Test connessione", systemImage: "bolt") { onTest() }
            Divider()
            Button("Modifica…", systemImage: "pencil") { onEdit() }
            Button("Elimina", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }

    private var subtitle: String {
        switch profile.mode {
        case .direct:
            return "\(profile.host):\(profile.port)"
        case .ssh:
            return "SSH · \(profile.sshHost):\(profile.sshPort) → \(profile.host):\(profile.port)"
        case .bridge:
            return "Bridge · \(profile.bridgeURL)"
        }
    }
}
