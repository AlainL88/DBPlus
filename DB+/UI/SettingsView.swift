//
//  SettingsView.swift
//  DB+
//
//  Impostazioni dell'app (per ora: blocco biometrico).
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("requireBiometricLock") private var requireBiometricLock = true
    @State private var showDebugLog = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Protezione") {
                    Toggle("Richiedi Face ID / Touch ID", isOn: $requireBiometricLock)
                        .help("Blocca l'app all'avvio e quando va in background.")
                }
                Section {
                    Text("Il blocco protegge l'accesso alle connessioni salvate. Se disattivato, l'app si apre direttamente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Debug") {
                    Button {
                        showDebugLog = true
                    } label: {
                        Label("Log di debug", systemImage: "ladybug")
                    }
                }
            }
            .navigationTitle("Impostazioni")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 260)
        .sheet(isPresented: $showDebugLog) {
            DebugLogView(log: DebugLog.shared)
        }
    }
}
