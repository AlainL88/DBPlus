//
//  SchemaNavigatorView.swift
//  DB+
//

import SwiftUI

struct SchemaNavigatorView: View {
    let session: ConnectionSession
    @Binding var selectedSchema: String?
    @Binding var selectedObject: SchemaNode?

    @State private var schemas: [String] = []
    @State private var children: [String: [SchemaNode]] = [:]
    @State private var expanded: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(schemas, id: \.self) { schema in
                schemaRow(schema)
            }
        }
        .listStyle(.sidebar)
        .task {
            await reload()
        }
        .onChange(of: session.isConnecting) { _, connecting in
            if !connecting {
                Task { await reload() }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Struttura")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Ricarica")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func schemaRow(_ schema: String) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(schema) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(schema)
                    loadChildrenIfNeeded(schema)
                } else {
                    expanded.remove(schema)
                }
            }
        )) {
            if let items = children[schema] {
                ForEach(items) { node in
                    Label(node.displayName, systemImage: node.symbolName)
                        .font(.callout)
                        .foregroundStyle(selectedObject?.id == node.id ? Color.accentColor : .primary)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSchema = schema
                            selectedObject = node
                        }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 12)
            }
        } label: {
            Label(schema, systemImage: "cylinder")
                .foregroundStyle(selectedSchema == schema && selectedObject == nil ? Color.accentColor : .primary)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSchema = schema
                    selectedObject = nil
                }
        }
    }

    private func loadChildrenIfNeeded(_ schema: String) {
        guard children[schema] == nil else { return }
        Task {
            do {
                let inspector = SchemaInspector(transport: try session.requireTransport())
                let items = try await inspector.children(of: schema)
                children[schema] = items
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        guard !session.isConnecting else {
            // Connessione in corso: verrà ricaricata quando finisce (onChange).
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let inspector = SchemaInspector(transport: try session.requireTransport())
            schemas = try await inspector.schemas()
            // Pre-carica lo schema selezionato / predefinito
            if selectedSchema == nil {
                let preferred = session.profile.defaultSchema.isEmpty ? schemas.first : session.profile.defaultSchema
                if let preferred {
                    selectedSchema = preferred
                    loadChildrenIfNeeded(preferred)
                }
            } else if let current = selectedSchema {
                loadChildrenIfNeeded(current)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
