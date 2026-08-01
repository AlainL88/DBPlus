//
//  SSHTransport.swift
//  DB+
//
//  Connessione via tunnel SSH: apre un port forwarding locale con OpenSSH
//  di sistema, poi si collega al database su 127.0.0.1:portaLocale
//  usando MySQLNIO (stesso percorso del trasporto diretto).
//

import Foundation

final class SSHTransport: DatabaseTransport {
    let mode: ConnectionMode = .ssh
    private(set) var isConnected = false

    private let profile: ConnectionProfile
    private let databasePassword: String?
    private let sshPassword: String?
    private let sshPassphrase: String?

    private let tunnel = SSHProcessTunnel()
    private var inner: DirectTransport?

    init(profile: ConnectionProfile, databasePassword: String?, sshPassword: String?, sshPassphrase: String?) {
        self.profile = profile
        self.databasePassword = databasePassword
        self.sshPassword = sshPassword
        self.sshPassphrase = sshPassphrase
    }

    func connect() async throws -> ServerInfo {
        let start = DispatchTime.now()
        let localPort = try await tunnel.start(profile: profile, password: sshPassword, passphrase: sshPassphrase)

        var localProfile = profile
        localProfile.host = "127.0.0.1"
        localProfile.port = localPort

        let inner = DirectTransport(profile: localProfile, password: databasePassword)
        self.inner = inner

        do {
            let info = try await inner.connect()
            self.isConnected = true
            let latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            return ServerInfo(version: info.version, host: profile.sshHost, latencyMS: latency, transportMode: .ssh)
        } catch {
            tunnel.teardown()
            self.inner = nil
            throw error
        }
    }

    func close() async {
        await inner?.close()
        inner = nil
        tunnel.teardown()
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
