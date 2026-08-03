//
//  ConnectingView.swift
//  DB+
//

import SwiftUI

/// Schermata di caricamento mostrata durante le attese di rete
/// (connessione e riconnessione). Centralizza lo stato "in corso".
struct ConnectingView: View {
    var message: String = "Connessione in corso…"
    var detail: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
