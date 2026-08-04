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
        _activeSchema = State(initialValue: defaultSchema)
        DebugLog.shared.log("[DB+DEBUG] QueryConsole init: defaultSchema ricevuto = '\(defaultSchema)'")
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
    /// Candidati per l'autocompletamento, separati per contesto.
    @State private var completionKeywords: [String] = SQLCompletion.keywords
    @State private var completionTables: [String] = []
    @State private var completionColumns: [String] = []
    /// Schema per cui sono già stati caricati i candidati (evita ricariche).
    @State private var loadedSchema: String?
    /// Database attivo per le query: inizializzato dallo schema passato
    /// all'apertura e modificabile dal picker in toolbar.
    @State private var activeSchema: String
    @State private var allSchemas: [String] = []

    @Environment(\.dismiss) private var dismiss

    /// Testo del placeholder: su iPhone non esiste il tasto Cmd per eseguire,
    /// quindi resta il semplice invito a scrivere la query.
    private var editorPlaceholder: String {
        #if os(macOS)
        "Scrivi qui la query…\nCmd+Invio per eseguire"
        #else
        "Scrivi qui la query…"
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SQLTextEditor(text: $sql,
                          completionKeywords: completionKeywords,
                          completionTables: completionTables,
                          completionColumns: completionColumns)
                .frame(minHeight: 160, maxHeight: 300)
                .overlay(alignment: .topLeading) {
                    if sql.isEmpty {
                        Text(editorPlaceholder)
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
        // Se si cambia il database dal picker a console aperta, ricarica
        // i candidati (tabelle e colonne del nuovo database).
        .onChange(of: activeSchema) { _, _ in
            Task { await loadCompletionCandidates() }
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            // Layout ampio (macOS): tutto in una riga.
            HStack(spacing: 8) {
                runButton
                clearButton
                exportButton
                Spacer()
                if !allSchemas.isEmpty {
                    schemaPicker
                        .frame(width: 160)
                }
                Text("Limite righe:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                rowLimitPicker
                    .frame(width: 110)
                closeButton
            }
            // Layout stretto (iPhone): azioni sopra, database + limite sotto.
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    runButton
                    clearButton
                    exportButton
                    Spacer()
                    closeButton
                }
                HStack(spacing: 8) {
                    if !allSchemas.isEmpty {
                        schemaPicker
                            .labelsHidden()
                            .frame(width: 120)
                    }
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

    /// Picker del database attivo: mostra su quale database si lavora e
    /// permette di cambiarlo prima di eseguire.
    private var schemaPicker: some View {
        Picker("Database:", selection: $activeSchema) {
            ForEach(allSchemas, id: \.self) { schema in
                Text(schema).tag(schema)
            }
        }
        .help("Database attivo: le query vengono eseguite qui")
    }

    private var runButton: some View {
        Button {
            runWithGuard()
        } label: {
            Label("Esegui", systemImage: "play.fill")
                .fixedSize()
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
            #if os(iOS)
            Image(systemName: "trash")
            #else
            Label("Svuota", systemImage: "trash")
            #endif
        }
        .help("Svuota l'editor e i risultati")
        .disabled(sql.isEmpty && results.isEmpty)
    }

    private var exportButton: some View {
        Button {
            exportResults()
        } label: {
            #if os(iOS)
            Image(systemName: "square.and.arrow.up")
            #else
            Label("Esporta", systemImage: "square.and.arrow.up")
            #endif
        }
        .help("Esporta i risultati in CSV")
        .disabled(!results.contains { $0.isSelect })
        .sheet(item: $exportShareItem) { item in
            CSVShareSheet(url: item.url)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(.borderless)
        .help("Chiudi la console")
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
            .scrollDismissesKeyboard(.immediately)
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
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if !activeSchema.isEmpty {
                Label(activeSchema, systemImage: "cylinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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

    /// Precarica i candidati per l'autocompletamento: keyword SQL più tabelle
    /// e colonne del database attivo. Popola anche l'elenco degli schemi
    /// (per il picker) e fissa il database attivo se vuoto.
    private func loadCompletionCandidates() async {
        // Idempotente: se i candidati sono già per questo schema, niente da fare.
        if loadedSchema == activeSchema { return }
        loadedSchema = activeSchema

        completionKeywords = SQLCompletion.keywords
        completionTables = []
        completionColumns = []
        do {
            let transport = try session.requireTransport()
            let inspector = SchemaInspector(transport: transport)
            let schemas = try await inspector.schemas()
            allSchemas = schemas
            DebugLog.shared.log("[DB+DEBUG] loadCandidates: schemi=\(schemas) activeSchema iniziale='\(activeSchema)'")
            // Database attivo: quello passato all'apertura se valido, altrimenti
            // il primo schema disponibile (mai "nessun database selezionato").
            if !schemas.contains(activeSchema) {
                DebugLog.shared.log("[DB+DEBUG] loadCandidates: '\(activeSchema)' non tra gli schemi → reset a '\(schemas.first ?? "")'")
                activeSchema = schemas.first ?? ""
            }
            DebugLog.shared.log("[DB+DEBUG] loadCandidates: activeSchema finale='\(activeSchema)'")
            if !activeSchema.isEmpty {
                let objects = (try? await inspector.children(of: activeSchema)) ?? []
                completionTables = objects
                    .filter { $0.kind == .table || $0.kind == .view }
                    .map { $0.displayName }
                completionColumns = (try? await inspector.columns(in: activeSchema)) ?? []
            }
        } catch {
            // Restano le sole keyword.
        }
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
            // Seleziona lo schema attivo prima di eseguire: senza database
            // le query falliscono con "nessun database selezionato".
            var schema = activeSchema
            if schema.isEmpty {
                schema = allSchemas.first ?? ""
            }
            if schema.isEmpty {
                schema = (try? await transport.listSchemas())?.first ?? ""
            }
            if !schema.isEmpty {
                try await transport.useSchema(schema)
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
