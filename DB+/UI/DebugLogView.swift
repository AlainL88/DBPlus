//
//  DebugLogView.swift
//  DB+
//
//  Foglio che mostra in-app il log di debug raccolto da `DebugLog`.
//  Temporaneo: da rimuovere a fine fase di test.
//

import SwiftUI

struct DebugLogView: View {
    @Bindable var log: DebugLog
    @Environment(\.dismiss) private var dismiss
    /// Mostra il log persistito su file (ultima sessione: sopravvive al crash,
    /// utile quando l'app si blocca e l'array in memoria va perso).
    @State private var showPersisted = false

    var body: some View {
        let lines = showPersisted
            ? log.readPersistedLog().split(separator: "\n").map(String.init)
            : log.snapshot()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Log debug")
                    .font(.headline)
                Spacer()
                Toggle("Registra", isOn: $log.enabled)
                    .labelsHidden()
                    .help("Abilita/disabilita la raccolta del debug")
                Toggle("File", isOn: $showPersisted)
                    .labelsHidden()
                    .help("Mostra il log persistito (ultima sessione)")
                Button("Copia") { PasteboardHelper.copy(lines.joined(separator: "\n")) }
                    .disabled(lines.isEmpty)
                Button("Pulisci") { log.clear() }
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            if lines.isEmpty {
                Spacer()
                Text("Nessun messaggio di debug.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }
}
