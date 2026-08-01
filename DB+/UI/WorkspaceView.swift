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

    var body: some View {
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
            QueryConsoleView(session: session)
                .frame(minWidth: 900, minHeight: 620)
        }
        .sheet(isPresented: $showBenchmark) {
            BenchmarkView(session: session, defaultSchema: selectedSchema ?? session.profile.defaultSchema)
                .frame(minWidth: 860, minHeight: 560)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let object = selectedObject {
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
        } else {
            ContentUnavailableView(
                "Seleziona uno schema o un oggetto",
                systemImage: "sidebar.left",
                description: Text("Scegli una tabella per esplorarne dati e struttura.")
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
