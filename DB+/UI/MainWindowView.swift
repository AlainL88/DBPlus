//
//  MainWindowView.swift
//  DB+
//

import SwiftUI

struct MainWindowView: View {
    @State private var store: ConnectionStore
    @State private var activeSession: ConnectionSession?
    @State private var selectedProfileID: UUID?
    @State private var showNewEditor = false
    @State private var showSettings = false
    @State private var editingProfile: ConnectionProfile?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var isConnecting = false

    init(store: ConnectionStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            #if os(iOS)
            // Su iOS compact la NavigationSplitView non naviga al dettaglio; mostriamo
            // direttamente il workspace quando la connessione è attiva. Il workspace ha
            // la sua NavigationStack interna (database → schema → tabella), quindi qui
            // niente stack annidata: due NavigationStack innestate rompono la navigazione
            // (tornava alla schermata principale selezionando un database).
            if let session = activeSession {
                WorkspaceView(session: session, onDisconnect: { Task { await disconnect() } })
            } else {
                sidebar
            }
            #else
            NavigationSplitView {
                sidebar
            } detail: {
                if let session = activeSession {
                    WorkspaceView(session: session, onDisconnect: { Task { await disconnect() } })
                } else {
                    welcomeView
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            #endif
        }
        .sheet(item: $editingProfile) { profile in
            // `.sheet(item:)` crea una view fresca a ogni modifica: gli @State
            // dell'editor vengono reinizializzati dai dati del profilo.
            ConnectionEditorView(profile: profile) { updated in
                store.upsert(updated)
                selectedProfileID = updated.id
                editingProfile = nil
            }
        }
        .sheet(isPresented: $showNewEditor) {
            ConnectionEditorView(profile: nil) { updated in
                store.upsert(updated)
                selectedProfileID = updated.id
                showNewEditor = false
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header: titolo + ingranaggio impostazioni in alto.
            HStack {
                Text("Connessioni")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.profiles) { profile in
                        ConnectionCardView(
                            profile: profile,
                            isActive: activeSession?.profile.id == profile.id,
                            isConnecting: isConnecting && activeSession?.profile.id == profile.id,
                            onConnect: { connect(to: profile) },
                            onTest: { test(profile) },
                            onEdit: { editingProfile = profile },
                            onDelete: { store.remove(profile) }
                        )
                    }
                    Button {
                        editingProfile = nil
                        showNewEditor = true
                    } label: {
                        Label("Nuova connessione", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundStyle(.tint.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .background(Color.groupedBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let session = activeSession, let info = session.serverInfo {
                    statusView(session, info)
                } else if let message = testResult {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private func statusView(_ session: ConnectionSession, _ info: ServerInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Connesso")
                    .font(.caption)
                    .bold()
            }
            Text("\(info.host) · \(info.version)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "Latenza handshake %.2f ms", info.latencyMS))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("DB+")
                .font(.largeTitle)
                .bold()
            Text("Gestore MySQL / MariaDB")
                .foregroundStyle(.secondary)
            if let testResult {
                Text(testResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 40)
            }
            HStack {
                Button("Test connessione") {
                    test(selectedProfile())
                }
                .disabled(isTesting || selectedProfile() == nil)
                Button("Apri connessioni…") {
                    editingProfile = nil
                    showNewEditor = true
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Actions

    /// Nessuna "connessione predefinita": si testa solo un profilo
    /// esplicitamente selezionato (selezionato in lista, connesso o modificato).
    private func selectedProfile() -> ConnectionProfile? {
        store.profile(id: selectedProfileID)
    }

    private func connect(to profile: ConnectionProfile) {
        // Evita connessioni concorrenti (tap + selezione lista) che causavano
        // stati confusi come "Nessuna connessione attiva" durante il tentativo.
        guard !isConnecting else { return }
        isConnecting = true
        selectedProfileID = profile.id
        let session = ConnectionSession(profile: profile)
        activeSession = session
        Task {
            await session.connect()
            isConnecting = false
            if session.errorMessage != nil {
                activeSession = nil
                testResult = session.errorMessage
            }
        }
    }

    private func test(_ profile: ConnectionProfile?) {
        guard let profile, !isTesting else { return }
        isTesting = true
        testResult = "Test in corso…"
        DebugLog.shared.log("[DB+DEBUG] test() inizio — mode=\(profile.mode.displayName) host=\(profile.host):\(profile.port) useTLS=\(profile.useTLS) ssh=\(profile.sshHost):\(profile.sshPort) auth=\(profile.sshAuthType.displayName)")
        Task {
            let result = await ConnectionSession(profile: profile).testConnection()
            DebugLog.shared.log("[DB+DEBUG] test() fine — risultato: \(result.prefix(200))")
            testResult = result
            isTesting = false
        }
    }

    private func disconnect() async {
        // Torna subito alla pagina iniziale; la chiusura della sessione prosegue in
        // background (il teardown del tunnel SSH può richiedere tempo o bloccarsi).
        let session = activeSession
        activeSession = nil
        await session?.disconnect()
    }
}
