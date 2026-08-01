//
//  SSHKeyGeneratorView.swift
//  DB+
//
//  Sheet per generare una coppia di chiavi Ed25519: nome + commento,
//  poi anteprima della chiave pubblica con copia/esportazione e
//  "Usa questa chiave" che restituisce il percorso della privata.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SSHKeyGeneratorView: View {
    var onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = "dbplus"
    @State private var comment = ""
    @State private var generated: GeneratedKey?
    @State private var errorMessage: String?
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Genera chiave Ed25519")
                .font(.headline)

            if let generated {
                resultView(generated)
            } else {
                formView
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 440)
        #if os(macOS)
        .frame(minHeight: 320)
        #endif
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Nome chiave (es. dbplus)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Commento (opzionale)", text: $comment)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Annulla") { dismiss() }
                Button("Genera chiave") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Risultato

    private func resultView(_ key: GeneratedKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Salvata in: \(key.privateKeyURL.lastPathComponent)")
                .font(.subheadline)

            Text("Chiave pubblica — incollala nel file authorized_keys del server")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(key.publicKeyLine)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 16) {
                Button("Copia") { PasteboardHelper.copy(key.publicKeyLine) }
                ShareLink(item: key.publicKeyURL) { Label("Esporta .pub", systemImage: "square.and.arrow.up") }
                ShareLink(item: key.privateKeyURL) { Label("Esporta .priv", systemImage: "lock") }
                #if os(macOS)
                Button("Mostra nel Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([key.privateKeyURL])
                }
                #endif
            }
            .buttonStyle(.borderless)

            Divider()

            HStack {
                Spacer()
                Button("Usa questa chiave") {
                    onSelect(key.privateKeyURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Azioni

    private func generate() {
        isGenerating = true
        errorMessage = nil
        do {
            generated = try SSHKeyGenerator.generateEd25519(name: name, comment: comment)
        } catch {
            errorMessage = "Generazione fallita: \(error.localizedDescription)"
        }
        isGenerating = false
    }
}
