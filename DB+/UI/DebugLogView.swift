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
    /// true = mostra il log persistito su file (sessione precedente).
    @State private var showPersisted = false
    @State private var lines: [String] = []
    @State private var logEnabled = true

    var body: some View {
        let displayed = showPersisted
            ? log.readPersistedLog().split(separator: "\n").map(String.init)
            : lines

        VStack(alignment: .leading, spacing: 12) {
            // Barra superiore essenziale: titolo + chiudi (niente sforamento).
            HStack {
                Text("Log debug")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            // Controlli con etichette e spiegazione.
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Registra log", isOn: $logEnabled)
                    .onChange(of: logEnabled) { _, value in log.enabled = value }
                Text("Raccoglie i messaggi di debug in memoria e su file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Mostra:")
                        .font(.callout)
                    Picker("", selection: $showPersisted) {
                        Text("Sessione corrente").tag(false)
                        Text("Ultima sessione (file)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text("Il file conserva l'ultima sessione anche dopo un crash; quella corrente è solo in memoria.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Contenuto: scroll verticale; le righe monospaced vanno a capo
            // (niente sforamento laterale).
            Group {
                if displayed.isEmpty {
                    Spacer()
                    Text("Nessun messaggio di debug.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
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

            HStack {
                Button("Copia") { PasteboardHelper.copy(displayed.joined(separator: "\n")) }
                    .disabled(displayed.isEmpty)
                Button("Pulisci") { log.clear(); refresh() }
                    .help("Cancella il log corrente e il file persistito")
                Spacer()
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
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
