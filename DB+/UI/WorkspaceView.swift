//
//  WorkspaceView.swift
//  DB+
//

import SwiftUI

/// Payload della console SQL: trasporta lo schema attivo nell'istante in cui
/// si preme "Query". Con .sheet(item:) la sheet riceve il valore direttamente
/// dal payload, senza leggere uno stato potenzialmente stale alla presentazione.
private struct QuerySheetPayload: Identifiable {
    let id = UUID()
    let schema: String
}

struct WorkspaceView: View {
    let session: ConnectionSession
    var onDisconnect: () -> Void = {}

    @State private var selectedSchema: String?
    @State private var selectedObject: SchemaNode?
    @State private var querySheet: QuerySheetPayload?
    @State private var showRetryFailed = false
    @State private var isReconnecting = false

    var body: some View {
        content
            .overlay {
                if session.isConnecting {
                    ConnectingView(message: "Connessione in corso…")
                }
            }
            .sheet(item: $querySheet) { payload in
                QueryConsoleView(session: session, defaultSchema: payload.schema)
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 620)
                    #endif
            }
            .onChange(of: session.connectionLost) { _, lost in
                if lost { Task { await autoRetry() } }
            }
            .alert("Impossibile riconnettere", isPresented: $showRetryFailed) {
                Button("Riprova") {
                    Task { await autoRetry() }
                }
                Button("Torna alla home", role: .destructive) { onDisconnect() }
            } message: {
                Text("Il server non risponde. Vuoi ritentare la connessione o tornare alla home?")
            }
    }

    /// Schema attivo: la selezione corrente, oppure lo schema del nodo
    /// selezionato (tabella/vista), altrimenti il default del profilo.
    private var activeSchema: String {
        if let selectedSchema { return selectedSchema }
        if let schema = selectedObject?.schemaName { return schema }
        return session.profile.defaultSchema
    }

    /// Ritenta automaticamente la connessione dopo una perdita; se fallisce
    /// anche il retry, mostra un avviso e torna indietro.
    private func autoRetry() async {
        guard !isReconnecting else { return }
        isReconnecting = true
        defer { isReconnecting = false }
        await session.disconnect()
        session.connectionLost = false
        await session.connect()
        if session.errorMessage != nil {
            showRetryFailed = true
        }
    }

    /// Su iOS (compact) una NavigationSplitView annidata dentro l'altra non
    /// presenta il dettaglio alla selezione: usiamo una NavigationStack a due
    /// livelli — elenco database → oggetti dello schema → dettaglio tabella.
    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        NavigationStack {
            DatabaseListView(session: session, onSelect: { selectedSchema = $0 })
                .navigationDestination(item: $selectedSchema) { schema in
                    SchemaObjectsView(session: session, schema: schema, onSelect: { selectedObject = $0 })
                        .navigationDestination(item: $selectedObject) { node in
                            detailView(for: node)
                        }
                        .toolbar {
                            ToolbarItemGroup {
                                Button {
                                    DebugLog.shared.log("[DB+DEBUG] Query iOS: apertura console su schema='\(schema)'")
                                    querySheet = QuerySheetPayload(schema: schema)
                                } label: {
                                    Label("Query", systemImage: "chevron.left.forwardslash.chevron.right")
                                }
                                .help("Apri la console SQL")

                                Button {
                                    onDisconnect()
                                } label: {
                                    Label("Disconnetti", systemImage: "power")
                                }
                                .help("Chiudi la connessione")
                            }
                        }
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            onDisconnect()
                        } label: {
                            Label("Disconnetti", systemImage: "power")
                        }
                        .help("Chiudi la connessione")
                    }
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
        .toolbar {
            ToolbarItemGroup {
                Button {
                    DebugLog.shared.log("[DB+DEBUG] Query macOS: apertura console su schema='\(activeSchema)' selected=\(selectedSchema ?? "nil")")
                    querySheet = QuerySheetPayload(schema: activeSchema)
                } label: {
                    Label("Query", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .help("Apri la console SQL")

                Button {
                    onDisconnect()
                } label: {
                    Label("Disconnetti", systemImage: "power")
                }
                .help("Chiudi la connessione")
            }
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
            TableDetailView(session: session, schema: object.schemaName ?? "", node: object)
        case .view:
            TableDetailView(session: session, schema: object.schemaName ?? "", node: object, isView: true)
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
