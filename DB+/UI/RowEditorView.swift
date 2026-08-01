//
//  RowEditorView.swift
//  DB+
//
//  Editor form per inserimento e modifica righe.
//  In modalità update le colonne PK sono mostrate in sola lettura.
//

import SwiftUI

enum RowEditorMode {
    case insert
    case update
}

struct RowEditorView: View {
    let structure: TableStructure
    let mode: RowEditorMode
    var onSave: ([String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var nullFlags: Set<String> = []

    init(structure: TableStructure, mode: RowEditorMode, existing: [String: CellValue]?, onSave: @escaping ([String: String]) -> Void) {
        self.structure = structure
        self.mode = mode
        self.onSave = onSave

        var initial: [String: String] = [:]
        for column in structure.columns {
            if mode == .update, let existing, let value = existing[column.name] {
                initial[column.name] = value.isNull ? "" : value.editString
            } else {
                initial[column.name] = ""
            }
        }
        _values = State(initialValue: initial)
    }

    private var editableColumns: [ColumnInfo] {
        if mode == .update {
            return structure.columns.filter { !structure.primaryKeyColumns.contains($0.name) }
        }
        return structure.columns
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .insert ? "Nuova riga" : "Modifica riga")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(structure.columns) { column in
                        columnRow(column)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .insert ? "Inserisci" : "Salva") {
                    onSave(values)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

    @ViewBuilder
    private func columnRow(_ column: ColumnInfo) -> some View {
        let isPK = structure.primaryKeyColumns.contains(column.name)
        let isEditable = editableColumns.contains(where: { $0.name == column.name })
        let isNull = nullFlags.contains(column.name)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(column.name)
                        .font(.system(size: 12, weight: .medium))
                    if isPK {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                Text(column.typeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)

            Toggle("NULL", isOn: Binding(
                get: { isNull },
                set: { on in
                    if on {
                        nullFlags.insert(column.name)
                    } else {
                        nullFlags.remove(column.name)
                    }
                }
            ))
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .disabled(!isEditable)

            TextField("", text: Binding(
                get: { values[column.name] ?? "" },
                set: { values[column.name] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .disabled(!isEditable || isNull)
        }
        .padding(.vertical, 2)
    }
}
