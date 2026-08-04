//
//  ConnectionCardView.swift
//  DB+
//
//  Card di connessione (variante "Card"): icona colorata per modalità,
//  host:porta, tag modalità e stato della connessione attiva.
//

import SwiftUI

struct ConnectionCardView: View {
    let profile: ConnectionProfile
    let isActive: Bool
    let isConnecting: Bool
    var onConnect: () -> Void = {}
    var onTest: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        Button(action: onConnect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    icon
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Text(hostLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    statusBadge
                }
                HStack(spacing: 8) {
                    modeTag
                    Spacer()
                }
            }
            .padding(14)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Test connessione", systemImage: "bolt") { onTest() }
            Divider()
            Button("Modifica…", systemImage: "pencil") { onEdit() }
            Button("Elimina", systemImage: "trash", role: .destructive) { onDelete() }
        }
        // Swipe a sinistra sulla cella → Elimina / Modifica / Test.
        // allowsFullSwipe: false per evitare eliminazioni accidentali.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Elimina", systemImage: "trash")
            }
            Button { onEdit() } label: {
                Label("Modifica", systemImage: "pencil")
            }
            Button { onTest() } label: {
                Label("Test", systemImage: "bolt")
            }
        }
    }

    // MARK: - Componenti

    private var icon: some View {
        ZStack {
            LinearGradient(colors: modeColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: profile.mode.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isConnecting {
            badge(text: "Connessione…", color: .orange)
        } else if isActive {
            badge(text: "Connessa", color: .green)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var modeTag: some View {
        Text(profile.mode.shortDisplayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tagColor)
            .background(tagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Dati

    private var hostLine: String {
        switch profile.mode {
        case .direct:
            return "\(profile.host):\(profile.port)"
        case .ssh:
            return "\(profile.sshHost):\(profile.sshPort) → \(profile.host)"
        case .bridge:
            return profile.bridgeURL
        }
    }

    private var modeColors: [Color] {
        switch profile.mode {
        case .direct:
            return [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.35, green: 0.79, blue: 0.98)]
        case .ssh:
            return [Color(red: 0.75, green: 0.35, blue: 0.95), Color(red: 0.82, green: 0.63, blue: 1.0)]
        case .bridge:
            return [Color(red: 1.0, green: 0.62, blue: 0.04), Color(red: 1.0, green: 0.84, blue: 0.04)]
        }
    }

    private var tagColor: Color {
        switch profile.mode {
        case .direct: return .blue
        case .ssh: return .purple
        case .bridge: return .orange
        }
    }
}
