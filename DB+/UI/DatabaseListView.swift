//
//  DatabaseListView.swift
//  DB+
//
//  Primo livello della navigazione iOS: elenco dei database.
//

import SwiftUI

#if os(iOS)
struct DatabaseListView: View {
    let session: ConnectionSession
    var onSelect: (String) -> Void = { _ in }

    @State private var schemas: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && schemas.isEmpty {
                ProgressView("Caricamento database…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, schemas.isEmpty {
                ContentUnavailableView(
                    "Impossibile caricare i database",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                List(schemas, id: \.self) { schema in
                    Button {
                        onSelect(schema)
                    } label: {
                        HStack {
                            Label(schema, systemImage: "cylinder")
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
                .listStyle(.plain)
            }
        }
        .navigationTitle("Database")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: session.isConnecting) { _, connecting in
            if !connecting { Task { await reload() } }
        }
    }

    private func reload() async {
        // Connessione in corso: resta in caricamento finché non è pronta.
        guard !session.isConnecting else {
            isLoading = true
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let inspector = SchemaInspector(transport: try session.requireTransport())
            schemas = try await inspector.schemas()
        } catch DBError.notConnected {
            // Trasporto non ancora pronto (connessione in avvio): il reload
            // viene rilanciato da onChange(isConnecting). Niente errore.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
