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
    let defaultSchema: String

    init(session: ConnectionSession, defaultSchema: String = "") {
        self.session = session
        self.defaultSchema = defaultSchema
    }

    @State private var sql = ""
    @State private var results: [StatementResult] = []
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var rowLimit = 1000
    @State private var statusText = ""
    @State private var showConfirm = false
    @State private var pendingVerdict: SQLGuard.Verdict?
    @State private var confirmProceed = false
    @State private var exportShareItem: FileShareItem?
    @State private var completionCandidates: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SQLTextEditor(text: $sql, completionCandidates: completionCandidates)
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
        .task { await loadCompletionCandidates() }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            // Layout ampio (macOS): tutto in una riga.
            HStack(spacing: 8) {
                runButton
                clearButton
                exportButton
                Spacer()
                Text("Limite righe:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                rowLimitPicker
                    .frame(width: 110)
                Button("Chiudi") { dismiss() }
            }
            // Layout stretto (iPhone): azioni sopra, limite sotto.
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    runButton
                    clearButton
                    exportButton
                    Spacer()
                    Button("Chiudi") { dismiss() }
                }
                HStack(spacing: 8) {
                    Text("Limite righe:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    rowLimitPicker
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var runButton: some View {
        Button {
            runWithGuard()
        } label: {
            Label("Esegui", systemImage: "play.fill")
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.borderedProminent)
        .disabled(isRunning || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var clearButton: some View {
        Button {
            sql = ""
            results = []
            statusText = ""
        } label: {
            Label("Svuota", systemImage: "trash")
        }
        .disabled(sql.isEmpty && results.isEmpty)
    }

    private var exportButton: some View {
        Button {
            exportResults()
        } label: {
            Label("Esporta", systemImage: "square.and.arrow.up")
        }
        .disabled(!results.contains { $0.isSelect })
        .sheet(item: $exportShareItem) { item in
            CSVShareSheet(url: item.url)
        }
    }

    private var rowLimitPicker: some View {
        Picker("", selection: $rowLimit) {
            Text("500").tag(500)
            Text("1.000").tag(1000)
            Text("5.000").tag(5000)
            Text("50.000").tag(50000)
        }
        .labelsHidden()
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

    /// Precarica i candidati per l'autocompletamento: keyword SQL più i
    /// nomi di schemi e oggetti del database attivo.
    private func loadCompletionCandidates() async {
        var candidates = SQLCompletion.keywords
        do {
            let transport = try session.requireTransport()
            let inspector = SchemaInspector(transport: transport)
            let schemas = try await inspector.schemas()
            candidates.append(contentsOf: schemas)
            let active = defaultSchema.isEmpty ? schemas.first : defaultSchema
            if let active, schemas.contains(active) {
                let objects = try? await inspector.children(of: active)
                candidates.append(contentsOf: objects?.map { $0.displayName } ?? [])
                let columns = try? await inspector.columns(in: active)
                candidates.append(contentsOf: columns ?? [])
            }
        } catch {
            // Restano le sole keyword.
        }
        completionCandidates = candidates
    }

    private func exportResults() {
        let content = CSVExporter.csv(results: results)
        guard !content.isEmpty else { return }
        #if os(macOS)
        CSVExporter.saveCSV(content, defaultName: "query_results")
        #else
        if let url = try? CSVExporter.writeTempCSV(named: "query_results", content: content) {
            exportShareItem = FileShareItem(url: url)
        }
        #endif
    }

    private func executeAll() async {
        isRunning = true
        errorMessage = nil
        results = []
        statusText = ""
        defer { isRunning = false }

        let start = DispatchTime.now()
        do {
            let transport = try session.requireTransport()
            // Seleziona lo schema (se noto) prima di eseguire: senza database
            // attivo le query falliscono con "nessun database selezionato".
            var activeSchema = defaultSchema
            if activeSchema.isEmpty {
                activeSchema = (try? await transport.listSchemas())?.first ?? ""
            }
            if !activeSchema.isEmpty {
                try await transport.useSchema(activeSchema)
            }
            let runner = QueryRunner(transport: transport)
            results = try await runner.runScript(sql, rowLimit: rowLimit) { _ in }
            let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            statusText = String(format: "Tempo totale: %.2f ms", total)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
