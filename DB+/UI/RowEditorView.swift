//
//  RowEditorView.swift
//  DB+
//
//  Editor form per inserimento e modifica righe.
//  In modalità update le colonne PK sono mostrate in sola lettura.
//  Il toggle NULL esplicita l'inserimento del valore nullo.
//

import SwiftUI

enum RowEditorMode {
    case insert
    case update
}

struct RowEditorView: View {
    let structure: TableStructure
    let mode: RowEditorMode
    var onSave: ([String: String], Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var nullFlags: Set<String> = []

    init(structure: TableStructure, mode: RowEditorMode, existing: [String: CellValue]?, onSave: @escaping ([String: String], Set<String>) -> Void) {
        self.structure = structure
        self.mode = mode
        self.onSave = onSave

        var initial: [String: String] = [:]
        var initialNulls: Set<String> = []
        for column in structure.columns {
            if mode == .update, let existing, let value = existing[column.name] {
                if value.isNull {
                    initialNulls.insert(column.name)
                }
                initial[column.name] = value.isNull ? "" : value.editString
            } else {
                initial[column.name] = ""
            }
        }
        _values = State(initialValue: initial)
        _nullFlags = State(initialValue: initialNulls)
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
                    onSave(values, nullFlags)
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

            Button {
                if isNull { nullFlags.remove(column.name) } else { nullFlags.insert(column.name) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isNull ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isNull ? Color.accentColor : Color.secondary)
                    Text("NULL")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isNull ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)

            Group {
                if isNull {
                    Text("NULL")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    TextField("", text: Binding(
                        get: { values[column.name] ?? "" },
                        set: { values[column.name] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .disabled(!isEditable)
        }
        .padding(.vertical, 2)
    }
}
