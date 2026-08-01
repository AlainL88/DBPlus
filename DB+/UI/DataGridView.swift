//
//  DataGridView.swift
//  DB+
//
//  Griglia dati ad alte prestazioni con:
//    - scroll orizzontale/verticale
//    - intestazioni cliccabili per l'ordinamento
//    - editing inline (doppio click su cella) con commit via callback
//

import SwiftUI

struct DataGridView: View {
    let columns: [ColumnHeader]
    let rows: [[CellValue]]
    let selectedRow: Int?
    let sortColumn: String?
    let ascending: Bool
    var onSelectRow: (Int) -> Void = { _ in }
    var onSortColumn: (String) -> Void = { _ in }
    var onEditCell: ((Int, Int, String) -> Void)? = nil

    @State private var editing: (row: Int, col: Int)?
    @State private var editText = ""
    #if os(macOS)
    @State private var hovered: (row: Int, col: Int)?
    #endif

    private let columnWidth: CGFloat = 160

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        rowView(rowIndex)
                    }
                } header: {
                    headerView
                }
            }
        }
        .background(Color.gridBackground)
        #if os(macOS)
        .onExitCommand { editing = nil }
        #endif
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            // Colonne numerazione
            ZStack {
                Color.gridBackground
            }
            .frame(width: 44, height: 28)
            .overlay(alignment: .bottom) { Divider() }
            .overlay(alignment: .leading) { Divider() }

            ForEach(0..<columns.count, id: \.self) { columnIndex in
                columnHeader(index: columnIndex)
            }
        }
        .background(Color.gridBackground)
    }

    private func columnHeader(index: Int) -> some View {
        let column = columns[index]
        return Button {
            onSortColumn(column.name)
        } label: {
            HStack(spacing: 3) {
                Text(column.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if sortColumn == column.name {
                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                }
                Text(column.typeName)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: columnWidth, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
        .overlay(alignment: .leading) { Divider().opacity(0.3) }
    }

    // MARK: - Righe

    @ViewBuilder
    private func rowView(_ rowIndex: Int) -> some View {
        let isSelected = selectedRow == rowIndex
        let row = rows[rowIndex]

        HStack(spacing: 0) {
            ZStack {
                isSelected ? Color.selectedRowBackground : Color.clear
            }
            .frame(width: 44, height: 24)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }
            .overlay(alignment: .leading) { Divider().opacity(0.3) }
            .overlay {
                Text("\(rowIndex + 1)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            ForEach(0..<columns.count, id: \.self) { colIndex in
                cellView(row: rowIndex, col: colIndex, value: row.count > colIndex ? row[colIndex] : .null, isSelected: isSelected)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectRow(rowIndex)
        }
    }

    private func cellView(row: Int, col: Int, value: CellValue, isSelected: Bool) -> some View {
        let isEditing = editing?.row == row && editing?.col == col
        let bg: Color = {
            if isSelected { return Color.selectedRowBackground }
            #if os(macOS)
            if hovered?.row == row { return Color.primary.opacity(0.05) }
            #endif
            return Color.clear
        }()

        return HStack(spacing: 0) {
            ZStack {
                bg
                if isEditing {
                    TextField("", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit {
                            commit(row: row, col: col)
                        }
                        #if os(macOS)
                        .onExitCommand {
                            editing = nil
                        }
                        #endif
                        .padding(.horizontal, 6)
                } else {
                    Text(display(value, at: col))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(value.isNull ? Color.secondary.opacity(0.6) : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: columnWidth, height: 24, alignment: .leading)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }
            .overlay(alignment: .leading) { Divider().opacity(0.3) }
        }
        #if os(macOS)
        .onHover { hovering in
            hovered = hovering ? (row: row, col: col) : nil
        }
        #endif
        .onTapGesture(count: 2) {
            guard onEditCell != nil else { return }
            editText = value.isNull ? "" : value.editString
            editing = (row: row, col: col)
        }
    }

    private func display(_ value: CellValue, at col: Int) -> String {
        if value.isNull { return "NULL" }
        if case .data(let d) = value {
            return "0x" + d.prefix(24).map { String(format: "%02X", $0) }.joined() + (d.count > 24 ? "…" : "")
        }
        return value.displayString
    }

    private func commit(row: Int, col: Int) {
        if let onEditCell {
            onEditCell(row, col, editText)
        }
        editing = nil
    }
}
