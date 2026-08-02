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
    @State private var showDebugLog = false
    @State private var debugLog = DebugLog.shared
    @State private var editingProfile: ConnectionProfile?
    @State private var testResult: String?
    @State private var isTesting = false

    init(store: ConnectionStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
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
        .sheet(isPresented: $showDebugLog) {
            DebugLogView(log: debugLog)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedProfileID) {
            Section("Connessioni") {
                ForEach(store.profiles) { profile in
                    ConnectionRowView(
                        profile: profile,
                        isActive: activeSession?.profile.id == profile.id,
                        isConnected: activeSession?.profile.id == profile.id
                    ) {
                        connect(to: profile)
                    } onTest: {
                        test(profile)
                    } onEdit: {
                        editingProfile = profile
                    } onDelete: {
                        store.remove(profile)
                    }
                }
                .onChange(of: selectedProfileID) { _, newValue in
                    if let profile = store.profile(id: newValue) {
                        connect(to: profile)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
                HStack {
                    Button {
                        editingProfile = nil
                        showNewEditor = true
                    } label: {
                        Label("Nuova connessione", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button {
                        showDebugLog = true
                    } label: {
                        Label("Log", systemImage: "ladybug")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
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

    private func selectedProfile() -> ConnectionProfile? {
        store.profile(id: selectedProfileID) ?? store.profiles.first
    }

    private func connect(to profile: ConnectionProfile) {
        selectedProfileID = profile.id
        let session = ConnectionSession(profile: profile)
        activeSession = session
        Task {
            await session.connect()
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
        await activeSession?.disconnect()
        activeSession = nil
    }
}
