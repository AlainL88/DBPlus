//
//  TableDetailView.swift
//  DB+
//

import SwiftUI

enum TableTab: String, CaseIterable {
    case data = "Dati"
    case structure = "Struttura"
}

struct TableDetailView: View {
    let session: ConnectionSession
    let schema: String
    let node: SchemaNode
    var isView: Bool = false

    @State private var tab: TableTab = .data
    @State private var structure: TableStructure?
    @State private var page = TablePage(columns: [], rows: [], total: 0, offset: 0, limit: 200)
    @State private var selectedRowIndex: Int?
    @State private var editingCell: (row: Int, col: Int)?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sortColumn: String?
    @State private var ascending = true
    @State private var filterText = ""
    @State private var showInsertEditor = false
    @State private var showDeleteConfirm = false
    @State private var statusMessage: String?
    @State private var exportShareItem: FileShareItem?

    private var tableName: String { node.displayName }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $tab) {
                ForEach(TableTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch tab {
            case .data:
                dataArea
            case .structure:
                structureArea
            }
        }
        .task { await loadInitial() }
        .sheet(isPresented: $showInsertEditor) {
            if let structure {
                RowEditorView(structure: structure, mode: .insert, existing: nil) { textMap, nulls in
                    showInsertEditor = false
                    var values: [String: CellValue] = [:]
                    for column in structure.columns {
                        let header = ColumnHeader(name: column.name, typeName: column.columnType,
                                                  isUnsigned: column.isUnsigned, index: column.ordinal - 1)
                        if nulls.contains(column.name) {
                            values[column.name] = .null
                        } else if let text = textMap[column.name] {
                            values[column.name] = CellValue.fromEditString(text, asHeader: header)
                        }
                    }
                    performInsert(values)
                }
            }
        }
        .confirmationDialog("Eliminare la riga selezionata?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { performDelete() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'operazione esegue un DELETE basato sulla chiave primaria.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: node.symbolName)
                .foregroundStyle(.tint)
            Text(tableName)
                .font(.title3)
                .bold()
            if isView {
                Text("Vista")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Area dati

    @ViewBuilder
    private var dataArea: some View {
        VStack(spacing: 0) {
            dataToolbar
            Divider()
            if page.rows.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Nessuna riga",
                    systemImage: "table",
                    description: Text(errorMessage ?? "La tabella non contiene righe per la pagina corrente.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataGridView(
                    columns: page.columns,
                    rows: page.rows,
                    selectedRow: selectedRowIndex,
                    sortColumn: sortColumn,
                    ascending: ascending,
                    onSelectRow: { selectedRowIndex = $0 },
                    onSortColumn: { column in
                        if sortColumn == column {
                            ascending.toggle()
                        } else {
                            sortColumn = column
                            ascending = true
                        }
                        Task { await reload() }
                    },
                    onEditCell: isView ? nil : performCellEdit,
                    onSelectCell: isView ? nil : { row, col in
                        editingCell = (row: row, col: col)
                    },
                    highlightedCell: editingCell
                )
            }
            if !isView, let cell = editingCell {
                CellEditorPanel(
                    column: page.columns[cell.col],
                    value: page.value(row: cell.row, column: cell.col),
                    onSave: { newText in
                        performCellEdit(row: cell.row, col: cell.col, newText: newText)
                        editingCell = nil
                    },
                    onCancel: { editingCell = nil }
                )
                // Cambiando cella SwiftUI riusa la stessa vista senza rieseguire
                // init(); .id() forza una nuova identità così lo stato del pannello
                // viene re-inizializzato con il valore della cella selezionata.
                .id("\(cell.row):\(cell.col)")
            }
            Divider()
            paginationBar
        }
    }

    private var dataToolbar: some View {
        ViewThatFits(in: .horizontal) {
            // Layout ampio (macOS): filtro e azioni in una riga.
            HStack(spacing: 8) {
                filterField
                    .frame(width: 280)
                Button("Applica") { applyFilter() }
                Spacer()
                actionButtons
            }
            // Layout stretto (iPhone): filtro sopra, azioni sotto.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    filterField
                    Button("Applica") { applyFilter() }
                }
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterField: some View {
        TextField("Filtro SQL (es. id > 100)", text: $filterText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { applyFilter() }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { showInsertEditor = true } label: { Label("Nuova riga", systemImage: "plus") }
                .disabled(isView)
            Button { Task { await reload() } } label: { Label("Ricarica", systemImage: "arrow.clockwise") }
            Button { exportData() } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
                .disabled(page.rows.isEmpty)
                .sheet(item: $exportShareItem) { item in
                    CSVShareSheet(url: item.url)
                }
            Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Elimina riga", systemImage: "trash") }
                .disabled(selectedRowIndex == nil || isView)
        }
    }

    private func applyFilter() {
        page = TablePage(columns: page.columns, rows: [], total: 0, offset: 0, limit: 200)
        Task { await reload() }
    }

    private var paginationBar: some View {
        HStack {
            Text("\(page.total) righe")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                page = TablePage(columns: page.columns, rows: [], total: page.total, offset: max(0, page.offset - page.limit), limit: page.limit)
                Task { await reload() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page.offset <= 0)
            Text("\(page.pageNumber) / \(page.totalPages)")
                .font(.caption)
                .monospacedDigit()
            Button {
                page = TablePage(columns: page.columns, rows: [], total: page.total, offset: page.offset + page.limit, limit: page.limit)
                Task { await reload() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(page.offset + page.limit >= page.total)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Area struttura

    @ViewBuilder
    private var structureArea: some View {
        if let structure {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection(structure)
                    columnsSection(structure)
                    if !structure.indexes.isEmpty { indexesSection(structure) }
                    if !structure.foreignKeys.isEmpty { foreignKeysSection(structure) }
                    if let createSQL = structure.createSQL {
                        createSQLSection(createSQL)
                    }
                }
                .padding(12)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summarySection(_ s: TableStructure) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], alignment: .leading, spacing: 16) {
            infoItem("Engine", s.engine ?? "—")
            infoItem("Collation", s.tableCollation ?? "—")
            infoItem("Auto-increment", s.autoIncrement.map(String.init) ?? "—")
            infoItem("Righe", s.rowCount.map(String.init) ?? "—")
        }
    }

    private func infoItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .monospacedDigit()
        }
    }

    private func columnsSection(_ s: TableStructure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Colonne")
                .font(.headline)
            Table(s.columns) {
                TableColumn("Colonna") { Text($0.name).fontWeight(.medium) }
                TableColumn("Tipo") { Text($0.typeDisplay).monospaced() }
                TableColumn("Null") { Text($0.isNullable ? "SÌ" : "NO") }
                TableColumn("Default") { Text($0.defaultValue ?? "NULL") }
                TableColumn("Extra") { Text($0.extra) }
                TableColumn("Collation") { Text($0.collation ?? "—") }
            }
            .frame(height: 220)
        }
    }

    private func indexesSection(_ s: TableStructure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Indici")
                .font(.headline)
            Table(s.indexes) {
                TableColumn("Nome") { Text($0.name).fontWeight(.medium) }
                TableColumn("Colonna") { Text($0.columnName).monospaced() }
                TableColumn("Sequenza") { Text(String($0.sequence)) }
                TableColumn("Unico") { Text($0.nonUnique ? "NO" : "SÌ") }
                TableColumn("Tipo") { Text($0.indexType) }
            }
            .frame(height: 140)
        }
    }

    private func foreignKeysSection(_ s: TableStructure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Foreign key")
                .font(.headline)
            Table(s.foreignKeys) {
                TableColumn("Vincolo") { Text($0.constraintName).fontWeight(.medium) }
                TableColumn("Colonna") { Text($0.columnName).monospaced() }
                TableColumn("Riferimento") { Text("\($0.referencedTable).\($0.referencedColumn)") }
                TableColumn("On Update") { Text($0.onUpdate) }
                TableColumn("On Delete") { Text($0.onDelete) }
            }
            .frame(height: 120)
        }
    }

    private func createSQLSection(_ sql: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SHOW CREATE")
                .font(.headline)
            ScrollView {
                Text(sql)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .frame(height: 200)
        }
    }

    // MARK: - Azioni

    private func makeService() throws -> DataGridService {
        DataGridService(transport: try session.requireTransport(), schema: schema, table: tableName)
    }

    private func loadInitial() async {
        do {
            let service = try makeService()
            let structData = try await service.loadStructure()
            structure = structData
            page = TablePage(columns: structData.columns.map {
                ColumnHeader(name: $0.name, typeName: $0.columnType, isUnsigned: $0.isUnsigned, index: $0.ordinal - 1)
            }, rows: [], total: 0, offset: 0, limit: 200)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let service = try makeService()
            let newPage = try await service.loadPage(
                offset: page.offset,
                sortColumn: sortColumn,
                ascending: ascending,
                filter: filterText
            )
            page = newPage
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pkValues(for rowIndex: Int) -> [String: CellValue] {
        guard let structure, rowIndex < page.rows.count else { return [:] }
        var result: [String: CellValue] = [:]
        for pkColumn in structure.primaryKeyColumns {
            if let colIdx = page.columns.firstIndex(where: { $0.name == pkColumn }) {
                result[pkColumn] = page.value(row: rowIndex, column: colIdx)
            }
        }
        return result
    }

    private func performCellEdit(row: Int, col: Int, newText: String) {
        guard row < page.rows.count else { return }
        let column = page.columns[col]
        let pk = pkValues(for: row)
        guard !pk.isEmpty else {
            statusMessage = "Impossibile modificare: manca la chiave primaria."
            return
        }
        let newValue = CellValue.fromEditString(newText, asHeader: column)
        let changed = [column.name: newValue]

        Task {
            do {
                let result = try await makeService().updateRow(pkValues: pk, changed: changed)
                statusMessage = result.isError ? (result.errorMessage ?? "Errore") : result.summary()
                await reload()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func performInsert(_ values: [String: CellValue]) {
        Task {
            do {
                let result = try await makeService().insertRow(values: values)
                statusMessage = result.isError ? (result.errorMessage ?? "Errore") : result.summary()
                await reload()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func exportData() {
        let content = CSVExporter.csv(columns: page.columns, rows: page.rows)
        #if os(macOS)
        CSVExporter.saveCSV(content, defaultName: "\(tableName)_data")
        #else
        if let url = try? CSVExporter.writeTempCSV(named: tableName, content: content) {
            exportShareItem = FileShareItem(url: url)
        }
        #endif
    }

    private func performDelete() {
        guard let selectedRowIndex else { return }
        let pk = pkValues(for: selectedRowIndex)
        guard !pk.isEmpty else {
            statusMessage = "Impossibile eliminare: manca la chiave primaria."
            return
        }
        Task {
            do {
                let result = try await makeService().deleteRow(pkValues: pk)
                statusMessage = result.isError ? (result.errorMessage ?? "Errore") : result.summary()
                await reload()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
