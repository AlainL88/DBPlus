//
//  QueryConsoleView.swift
//  DB+
//
//  Workbench SQL: editor evidenziato, esecuzione multi-statement,
//  protezione delle operazioni distruttive, tempi in ms e conteggi.
//

import SwiftUI

struct QueryConsoleView: View {
    let session: ConnectionSession

    @State private var sql = ""
    @State private var results: [StatementResult] = []
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var rowLimit = 1000
    @State private var statusText = ""
    @State private var showConfirm = false
    @State private var pendingVerdict: SQLGuard.Verdict?
    @State private var confirmProceed = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SQLTextEditor(text: $sql)
                .frame(minHeight: 160, maxHeight: 300)
                .overlay(alignment: .topLeading) {
                    if sql.isEmpty {
                        Text("Scrivi qui la query…\nCmd+Invio per eseguire")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(8)
            Divider()
            resultsArea
            Divider()
            statusBar
        }
        .confirmationDialog(pendingVerdict?.message ?? "",
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Esegui comunque", role: .destructive) {
                confirmProceed = true
                Task { await executeAll() }
            }
            Button("Annulla", role: .cancel) {
                confirmProceed = false
            }
        } message: {
            Text("Operazione ad alto rischio rilevata.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                runWithGuard()
            } label: {
                Label("Esegui", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                sql = ""
                results = []
                statusText = ""
            } label: {
                Label("Svuota", systemImage: "trash")
            }
            .disabled(sql.isEmpty && results.isEmpty)

            Spacer()

            Text("Limite righe:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $rowLimit) {
                Text("500").tag(500)
                Text("1.000").tag(1000)
                Text("5.000").tag(5000)
                Text("50.000").tag(50000)
            }
            .labelsHidden()
            .frame(width: 110)

            Button("Chiudi") { dismiss() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if isRunning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Esecuzione…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ScrollView {
                Text(errorMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                "Nessun risultato",
                systemImage: "text.cursor",
                description: Text("Esegui una query per vedere i risultati.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if results.count == 1 {
                QueryResultView(result: results[0])
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Statement \(index + 1)")
                                        .font(.caption)
                                        .bold()
                                    Text(result.summary())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f ms", result.executionTimeMS))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.underPageBackground)
                                Divider()
                                QueryResultView(result: result)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.separatorLine))
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !results.isEmpty {
                let rows = results.reduce(0) { $0 + $1.rows.count }
                let affected = results.reduce(0) { $0 + Int($1.affectedRows) }
                Text("\(results.count) statement · \(rows) righe restituite · \(affected) righe modificate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Esecuzione

    private func runWithGuard() {
        let statements = SQLSplitter.split(sql)
        guard !statements.isEmpty else { return }

        let risky = statements.first { SQLGuard.assess($0).requiresConfirmation }
        if let risky {
            pendingVerdict = SQLGuard.assess(risky)
            showConfirm = true
            return
        }
        Task { await executeAll() }
    }

    private func executeAll() async {
        isRunning = true
        errorMessage = nil
        results = []
        statusText = ""
        defer { isRunning = false }

        let start = DispatchTime.now()
        do {
            let runner = QueryRunner(transport: try session.requireTransport())
            results = try await runner.runScript(sql, rowLimit: rowLimit) { _ in }
            let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            statusText = String(format: "Tempo totale: %.2f ms", total)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
