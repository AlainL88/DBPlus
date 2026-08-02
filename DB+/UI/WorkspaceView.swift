//
//  WorkspaceView.swift
//  DB+
//

import SwiftUI

struct WorkspaceView: View {
    let session: ConnectionSession
    var onDisconnect: () -> Void = {}

    @State private var selectedSchema: String?
    @State private var selectedObject: SchemaNode?
    @State private var showQueryConsole = false
    @State private var showBenchmark = false
    @State private var showConnectionLost = false
    @State private var showRetryFailed = false

    var body: some View {
        content
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showQueryConsole = true
                    } label: {
                        Label("Query", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Apri la console SQL")

                    Button {
                        showBenchmark = true
                    } label: {
                        Label("Benchmark", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    .help("Esegui benchmarking")

                    Button {
                        onDisconnect()
                    } label: {
                        Label("Disconnetti", systemImage: "power")
                    }
                    .help("Chiudi la connessione")
                }
            }
            .sheet(isPresented: $showQueryConsole) {
                QueryConsoleView(session: session, defaultSchema: selectedSchema ?? session.profile.defaultSchema)
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 620)
                    #endif
            }
            .sheet(isPresented: $showBenchmark) {
                BenchmarkView(session: session, defaultSchema: selectedSchema ?? session.profile.defaultSchema)
                    #if os(macOS)
                    .frame(minWidth: 860, minHeight: 560)
                    #endif
            }
            .onChange(of: session.connectionLost) { _, lost in
                if lost { showConnectionLost = true }
            }
            .alert("Connessione persa", isPresented: $showConnectionLost) {
                Button("Riprova") { Task { await retryConnection() } }
                Button("Torna indietro", role: .cancel) { onDisconnect() }
            } message: {
                Text("La connessione al server è scaduta. Riprova oppure torna alla lista delle connessioni.")
            }
            .alert("Impossibile riconnettere", isPresented: $showRetryFailed) {
                Button("OK") { onDisconnect() }
            } message: {
                Text("Il server non risponde. Tornerai alla lista delle connessioni.")
            }
    }

    /// Tenta di riconnettere dopo una perdita di connessione; se fallisce,
    /// mostra un secondo avviso e torna indietro.
    private func retryConnection() async {
        await session.disconnect()
        session.connectionLost = false
        await session.connect()
        if session.errorMessage != nil {
            showRetryFailed = true
        }
    }

    /// Su iOS (compact) una NavigationSplitView annidata dentro l'altra non
    /// presenta il dettaglio alla selezione: usiamo una NavigationStack con
    /// navigationDestination, che spinge la TableDetailView.
    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        NavigationStack {
            SchemaNavigatorView(
                session: session,
                selectedSchema: $selectedSchema,
                selectedObject: $selectedObject
            )
            .navigationDestination(item: $selectedObject) { node in
                detailView(for: node)
            }
        }
        #else
        NavigationSplitView {
            SchemaNavigatorView(
                session: session,
                selectedSchema: $selectedSchema,
                selectedObject: $selectedObject
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detailView
        }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        if let object = selectedObject {
            detailView(for: object)
        } else {
            ContentUnavailableView(
                "Seleziona uno schema o un oggetto",
                systemImage: "sidebar.left",
                description: Text("Scegli una tabella per esplorarne dati e struttura.")
            )
        }
    }

    @ViewBuilder
    private func detailView(for object: SchemaNode) -> some View {
        switch object.kind {
        case .table:
            TableDetailView(session: session, schema: selectedSchema ?? "", node: object)
        case .view:
            TableDetailView(session: session, schema: selectedSchema ?? "", node: object, isView: true)
        case .database:
            DatabaseDetailView(schema: object.displayName)
        default:
            ContentUnavailableView(
                "Routine",
                systemImage: "function",
                description: Text("Il dettaglio delle stored procedure verrà aggiunto in una release futura.")
            )
        }
    }
}

struct DatabaseDetailView: View {
    let schema: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(schema)
                .font(.title2)
                .bold()
            Text("Espandi lo schema nella barra laterale per vedere tabelle, viste e routine.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
