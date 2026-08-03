//
//  SchemaObjectsView.swift
//  DB+
//
//  Secondo livello della navigazione iOS: oggetti (tabelle, viste, routine)
//  del database selezionato. Qui vive il tasto Query.
//

import SwiftUI

#if os(iOS)
struct SchemaObjectsView: View {
    let session: ConnectionSession
    let schema: String
    var onSelect: (SchemaNode) -> Void = { _ in }

    @State private var items: [SchemaNode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var tables: [SchemaNode] { items.filter { $0.kind == .table } }
    private var views: [SchemaNode] { items.filter { $0.kind == .view } }
    private var routines: [SchemaNode] { items.filter { $0.kind == .procedure || $0.kind == .function } }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Caricamento…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView(
                    "Nessun oggetto",
                    systemImage: "table",
                    description: Text(errorMessage)
                )
            } else {
                List {
                    if !tables.isEmpty {
                        Section("Tabelle") {
                            ForEach(tables) { node in row(node) }
                        }
                    }
                    if !views.isEmpty {
                        Section("Viste") {
                            ForEach(views) { node in row(node) }
                        }
                    }
                    if !routines.isEmpty {
                        Section("Routine") {
                            ForEach(routines) { node in row(node) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(schema)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ node: SchemaNode) -> some View {
        Button {
            onSelect(node)
        } label: {
            HStack {
                Label(node.displayName, systemImage: node.symbolName)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func load() async {
        guard !session.isConnecting else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let inspector = SchemaInspector(transport: try session.requireTransport())
            items = try await inspector.children(of: schema)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
