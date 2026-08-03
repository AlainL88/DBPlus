//
//  CellEditorPanel.swift
//  DB+
//
//  Pannello di modifica cella tipo-consapevole: editor adatto al tipo del campo
//  (date / datetime / timestamp / numerici / testo) con gestione esplicita del NULL.
//

import SwiftUI

struct CellEditorPanel: View {
    let column: ColumnHeader
    let value: CellValue
    let onSave: (String) -> Void
    let onCancel: () -> Void

    private enum EditKind {
        case dateOnly
        case dateTime
        case numeric
        case text
    }

    @State private var text: String
    @State private var dateValue: Date
    @State private var isNull: Bool

    private let kind: EditKind

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(column: ColumnHeader, value: CellValue,
         onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.column = column
        self.value = value
        self.onSave = onSave
        self.onCancel = onCancel
        self.kind = Self.kind(for: column.typeName)
        _text = State(initialValue: value.isNull ? "" : value.editString)
        _isNull = State(initialValue: value.isNull)
        _dateValue = State(initialValue: Self.dateFrom(value) ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Modifica \(column.name)", systemImage: "pencil")
                    .font(.headline)
                Spacer()
                Text(column.typeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            switch kind {
            case .dateOnly:
                DatePicker("", selection: $dateValue, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(isNull)
            case .dateTime:
                DatePicker("", selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .disabled(isNull)
            case .numeric, .text:
                TextField("Valore", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isNull)
                    #if os(iOS)
                    .keyboardType(kind == .numeric ? .numbersAndPunctuation : .default)
                    #endif
            }

            Toggle("Imposta NULL", isOn: $isNull)

            HStack {
                Button("Annulla", role: .cancel) { onCancel() }
                Spacer()
                Button("Salva") { onSave(commitString()) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.background)
    }

    private func commitString() -> String {
        if isNull { return "" }
        switch kind {
        case .dateOnly:
            return Self.dateOnlyFormatter.string(from: dateValue)
        case .dateTime:
            return Self.dateTimeFormatter.string(from: dateValue)
        case .numeric, .text:
            return text
        }
    }

    private static func kind(for type: String) -> EditKind {
        let t = type.lowercased()
        if t == "date" { return .dateOnly }
        if t == "datetime" || t == "timestamp" { return .dateTime }
        if t.contains("int") || t == "year" || t == "decimal"
            || t == "float" || t == "double" || t == "bit" {
            return .numeric
        }
        return .text
    }

    private static func dateFrom(_ value: CellValue) -> Date? {
        if case .date(let d) = value { return d }
        let s = value.isNull ? "" : value.displayString
        if s.isEmpty { return nil }
        return dateTimeFormatter.date(from: s) ?? dateOnlyFormatter.date(from: s)
    }
}
