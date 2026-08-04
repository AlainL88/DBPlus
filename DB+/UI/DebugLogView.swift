//
//  DebugLogView.swift
//  DB+
//
//  Foglio che mostra in-app il log di debug raccolto da `DebugLog`.
//  Temporaneo: da rimuovere a fine fase di test.
//

import SwiftUI

struct DebugLogView: View {
    var log: DebugLog
    @Environment(\.dismiss) private var dismiss
    /// Mostra il log persistito su file (ultima sessione: sopravvive al crash).
    @State private var showPersisted = false
    @State private var lines: [String] = []
    @State private var logEnabled = true

    var body: some View {
        let displayed = showPersisted
            ? log.readPersistedLog().split(separator: "\n").map(String.init)
            : lines
        VStack(alignment: .leading, spacing: 8) {
            // Barra superiore: titolo + due controlli con ETICHETTA VISIBILE
            // (prima erano labelsHidden → due switch senza significato).
            HStack(spacing: 12) {
                Text("Log debug")
                    .font(.headline)
                Spacer()
                Toggle("Registra", isOn: $logEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: logEnabled) { _, value in log.enabled = value }
                    .help("Abilita/disabilita la raccolta del debug")
                Toggle("File", isOn: $showPersisted)
                    .toggleStyle(.switch)
                    .help("Mostra il log persistito (ultima sessione)")
                Button("Copia") { PasteboardHelper.copy(displayed.joined(separator: "\n")) }
                    .disabled(displayed.isEmpty)
                Button("Pulisci") { log.clear(); refresh() }
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            if displayed.isEmpty {
                Spacer()
                Text("Nessun messaggio di debug.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(displayed.enumerated()), id: \.offset) { _, line in
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
        .onAppear {
            logEnabled = log.enabled
            refresh()
        }
        .task {
            // Polling: DebugLog non è più osservabile; aggiorniamo la UI qui.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func refresh() {
        lines = log.snapshot()
    }
}
