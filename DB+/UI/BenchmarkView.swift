//
//  BenchmarkView.swift
//  DB+
//
//  Strumento di benchmarking: latenza, throughput, memoria, resilienza.
//  Report esportabile in formato testo.
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct BenchmarkView: View {
    let session: ConnectionSession
    var defaultSchema: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var schema = ""
    @State private var schemas: [String] = []
    @State private var sizes: Set<Int> = [1_000, 10_000, 50_000]
    @State private var metrics: [BenchmarkMetric] = []
    @State private var isRunning = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .task {
            await loadSchemas()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Schema:")
                .font(.callout)
            Picker("", selection: $schema) {
                ForEach(schemas, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            Text("Dataset:")
                .font(.callout)
            Toggle("1k", isOn: Binding(
                get: { sizes.contains(1_000) },
                set: { on in
                    if on { sizes.insert(1_000) } else { sizes.remove(1_000) }
                }
            ))
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            Toggle("10k", isOn: Binding(
                get: { sizes.contains(10_000) },
                set: { on in
                    if on { sizes.insert(10_000) } else { sizes.remove(10_000) }
                }
            ))
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            Toggle("50k", isOn: Binding(
                get: { sizes.contains(50_000) },
                set: { on in
                    if on { sizes.insert(50_000) } else { sizes.remove(50_000) }
                }
            ))
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif

            Spacer()

            Button {
                Task { await run() }
            } label: {
                Label("Esegui benchmark", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning || schema.isEmpty || sizes.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isRunning {
            VStack(spacing: 10) {
                ProgressView()
                Text(statusMessage ?? "Esecuzione…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Errore nel benchmark",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if metrics.isEmpty {
            ContentUnavailableView(
                "Benchmark",
                systemImage: "gauge.with.dots.needle.50percent",
                description: Text("Configura lo schema di test e avvia. Verrà creata e rimossa una tabella temporanea \("__dbplus_bench").")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(metrics) { metric in
                HStack(spacing: 12) {
                    Text(metric.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(metric.name)
                        .font(.callout)
                    Spacer()
                    Text(metric.value)
                        .font(.callout)
                        .monospacedDigit()
                        .fontWeight(.medium)
                    Text(metric.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            #if os(macOS)
            Button("Esporta report…") {
                exportReport()
            }
            .disabled(metrics.isEmpty)
            #endif
            Button("Chiudi") { dismiss() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Azioni

    private func loadSchemas() async {
        do {
            schemas = try await session.requireTransport().listSchemas()
            if schema.isEmpty {
                schema = defaultSchema.isEmpty ? (schemas.first ?? "") : defaultSchema
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        statusMessage = "Esecuzione benchmark…"
        defer { isRunning = false }
        do {
            let service = BenchmarkService(transport: try session.requireTransport(), schema: schema)
            metrics = try await service.run(datasetSizes: sizes.sorted())
            statusMessage = "Benchmark completato (\(metrics.count) metriche)."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    #if os(macOS)
    private func exportReport() {
        var lines: [String] = []
        lines.append("DB+ — Report di benchmarking")
        lines.append("Data: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("Schema: \(schema)")
        lines.append("")
        for metric in metrics {
            lines.append("\(metric.category) | \(metric.name) | \(metric.value) | \(metric.note)")
        }
        lines.append("")
        lines.append("Note: latenza handshake misurata nel connect(); footprint via task_info;")
        lines.append("resilienza: ServerAliveInterval=15s (SSH), timeout URLSession (bridge).")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DBplus_benchmark_\(Date().formatted(.iso8601)).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Report esportato."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}
