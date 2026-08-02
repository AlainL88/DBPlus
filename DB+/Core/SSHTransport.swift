//
//  SSHTransport.swift
//  DB+
//
//  Connessione via tunnel SSH: apre un port forwarding locale (OpenSSH di
//  sistema su macOS, client SSH in-process su iOS), poi si collega al database
//  su 127.0.0.1:portaLocale usando MySQLNIO (stesso percorso del trasporto diretto).
//

import Foundation

final class SSHTransport: DatabaseTransport {
    let mode: ConnectionMode = .ssh
    private(set) var isConnected = false

    private let profile: ConnectionProfile
    private let databasePassword: String?
    private let sshPassword: String?
    private let sshPassphrase: String?

    private let tunnel: SSHTunnel
    private var inner: DirectTransport?

    init(profile: ConnectionProfile, databasePassword: String?, sshPassword: String?, sshPassphrase: String?) {
        self.profile = profile
        self.databasePassword = databasePassword
        self.sshPassword = sshPassword
        self.sshPassphrase = sshPassphrase
        #if os(macOS)
        self.tunnel = SSHProcessTunnel()
        #else
        self.tunnel = SSHInProcessTunnel()
        #endif
    }

    func connect() async throws -> ServerInfo {
        let start = DispatchTime.now()
        DebugLog.shared.log("[DB+DEBUG] SSHTransport.connect() sshHost=\(profile.sshHost):\(profile.sshPort) user=\(profile.sshUsername) auth=\(profile.sshAuthType.displayName)")
        DebugLog.shared.log("[DB+DEBUG]   -> tunnel.start(): inizio")
        let localPort = try await tunnel.start(profile: profile, password: sshPassword, passphrase: sshPassphrase, timeout: 30)
        DebugLog.shared.log("[DB+DEBUG]   -> tunnel.start(): OK — porta locale=\(localPort)")

        var localProfile = profile
        localProfile.host = "127.0.0.1"
        localProfile.port = localPort

        let inner = DirectTransport(profile: localProfile, password: databasePassword)
        self.inner = inner

        do {
            DebugLog.shared.log("[DB+DEBUG]   -> DirectTransport inner (127.0.0.1:\(localPort)): inizio")
            let info = try await inner.connect()
            DebugLog.shared.log("[DB+DEBUG]   -> DirectTransport inner: OK — version=\(info.version)")
            self.isConnected = true
            let latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            return ServerInfo(version: info.version, host: profile.sshHost, latencyMS: latency, transportMode: .ssh)
        } catch {
            DebugLog.shared.log("[DB+DEBUG]   -> DirectTransport inner ERRORE: \(error.localizedDescription)")
            await tunnel.teardown()
            self.inner = nil
            throw error
        }
    }

    func close() async {
        await inner?.close()
        inner = nil
        await tunnel.teardown()
        isConnected = false
    }

    private func requireInner() throws -> DirectTransport {
        guard let inner, inner.isConnected else { throw DBError.notConnected }
        return inner
    }

    // MARK: - Delegazione

    func pingLatency() async throws -> Double {
        try await requireInner().pingLatency()
    }

    func execute(_ request: StatementRequest) async throws -> StatementResult {
        try await requireInner().execute(request)
    }

    func stream(_ sql: String, onRow: @escaping @Sendable ([CellValue]) async throws -> Void) async throws -> Int {
        try await requireInner().stream(sql, onRow: onRow)
    }

    func listSchemas() async throws -> [String] {
        try await requireInner().listSchemas()
    }

    func listTables(schema: String) async throws -> [String] {
        try await requireInner().listTables(schema: schema)
    }

    func listViews(schema: String) async throws -> [String] {
        try await requireInner().listViews(schema: schema)
    }

    func listRoutines(schema: String, kind: String) async throws -> [String] {
        try await requireInner().listRoutines(schema: schema, kind: kind)
    }

    func tableStructure(schema: String, table: String) async throws -> TableStructure {
        try await requireInner().tableStructure(schema: schema, table: table)
    }

    func tableRowCount(schema: String, table: String) async throws -> Int {
        try await requireInner().tableRowCount(schema: schema, table: table)
    }

    func primaryKeyColumns(schema: String, table: String) async throws -> [String] {
        try await requireInner().primaryKeyColumns(schema: schema, table: table)
    }

    func useSchema(_ schema: String) async throws {
        try await requireInner().useSchema(schema)
    }
}
