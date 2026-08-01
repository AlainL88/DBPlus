//
//  QueryResultView.swift
//  DB+
//
//  Visualizzazione del risultato di una singola istruzione SQL.
//

import SwiftUI

struct QueryResultView: View {
    let result: StatementResult

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            if result.isError {
                Label("Errore", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if result.isSelect {
                Label(result.summary(), systemImage: "tablecells")
            } else {
                Label(result.summary(), systemImage: "checkmark.circle")
            }
            Spacer()
            Text(String(format: "%.2f ms", result.executionTimeMS))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if result.isError {
            ScrollView {
                Text(result.errorMessage ?? "Errore sconosciuto")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        } else if result.isSelect {
            DataGridView(
                columns: result.columns,
                rows: result.rows,
                selectedRow: nil,
                sortColumn: nil,
                ascending: true,
                onSelectRow: { _ in },
                onSortColumn: { _ in }
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Righe modificate: \(result.affectedRows)")
                if let lastID = result.lastInsertID {
                    Text("Ultimo ID inserito: \(lastID)")
                }
                if result.truncated {
                    Text("⚠ Risultato troncato al limite impostato.")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
