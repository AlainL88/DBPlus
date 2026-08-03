//
//  CSVExporter.swift
//  DB+
//
//  Esportazione dei dati in formato CSV (RFC 4180): save-panel su macOS,
//  share-sheet su iOS.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Item identificabile per presentare un file condiviso (iOS).
struct FileShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum CSVExporter {

    /// Converte colonne e righe in CSV. I NULL diventano celle vuote.
    static func csv(columns: [ColumnHeader], rows: [[CellValue]]) -> String {
        var out = ""
        out += columns.map { escape($0.name) }.joined(separator: ",") + "\n"
        for row in rows {
            let cells = columns.indices.map { idx -> String in
                let value = row.count > idx ? row[idx] : .null
                return escape(value.isNull ? "" : value.displayString)
            }
            out += cells.joined(separator: ",") + "\n"
        }
        return out
    }

    /// CSV di tutti i risultati SELECT, separati da una riga di commento.
    static func csv(results: [StatementResult]) -> String {
        let selects = results.enumerated().filter { $0.element.isSelect }
        guard !selects.isEmpty else { return "" }
        var out = ""
        for (index, result) in selects {
            if index > 0 {
                out += "\n--- Statement \(index + 1) ---\n"
            }
            out += csv(columns: result.columns, rows: result.rows)
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// Scrive il contenuto su un file temporaneo e ne ritorna l'URL.
    static func writeTempCSV(named: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DBplus_\(sanitized(named)).csv")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    #if os(macOS)
    /// Salva su disco tramite NSSavePanel.
    static func saveCSV(_ content: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(sanitized(defaultName)).csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.data(using: .utf8)?.write(to: url)
        }
    }
    #endif

    private static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "_-"))
        return name.components(separatedBy: allowed.inverted).joined()
    }
}

/// Schermata di condivisione del file CSV (ShareLink).
struct CSVShareSheet: View {
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Text("File CSV pronto per la condivisione")
                .foregroundStyle(.secondary)
            ShareLink(item: url) {
                Label("Condividi CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
