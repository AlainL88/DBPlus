//
//  ConnectionSession.swift
//  DB+
//
//  Sessione attiva verso un database: gestisce il trasporto, la connessione,
//  il test di connessione e le operazioni di alto livello.
//

import Foundation
import Observation

@Observable
final class ConnectionSession {
    let profile: ConnectionProfile
    private(set) var transport: (any DatabaseTransport)?
    private(set) var serverInfo: ServerInfo?
    var errorMessage: String?
    var statusMessage: String?
    var isConnecting = false

    private struct Secrets {
        var databasePassword: String?
        var sshPassword: String?
        var sshPassphrase: String?
        var bridgeToken: String?
        var bridgeHMACSecret: String?
    }

    private var secrets: Secrets

    init(profile: ConnectionProfile) {
        self.profile = profile
        self.secrets = Secrets(
            databasePassword: SecretStore.load(profileID: profile.id, kind: .databasePassword),
            sshPassword: SecretStore.load(profileID: profile.id, kind: .sshPassword),
            sshPassphrase: SecretStore.load(profileID: profile.id, kind: .sshPassphrase),
            bridgeToken: SecretStore.load(profileID: profile.id, kind: .bridgeToken),
            bridgeHMACSecret: SecretStore.load(profileID: profile.id, kind: .bridgeHMACSecret)
        )
    }

    // MARK: - Connessione

    func connect() async {
        isConnecting = true
        errorMessage = nil
        statusMessage = nil
        defer { isConnecting = false }

        await disconnect()

        let newTransport: any DatabaseTransport
        switch profile.mode {
        case .direct:
            newTransport = DirectTransport(profile: profile, password: secrets.databasePassword)
        case .ssh:
            newTransport = SSHTransport(
                profile: profile,
                databasePassword: secrets.databasePassword,
                sshPassword: secrets.sshPassword,
                sshPassphrase: secrets.sshPassphrase
            )
        case .bridge:
            newTransport = BridgeTransport(
                profile: profile,
                token: secrets.bridgeToken,
                hmacSecret: secrets.bridgeHMACSecret
            )
        }

        do {
            let info = try await newTransport.connect()
            transport = newTransport
            serverInfo = info
            statusMessage = "Connesso a \(info.host) · \(info.version)"
        } catch {
            errorMessage = error.localizedDescription
            await newTransport.close()
        }
    }

    func disconnect() async {
        await transport?.close()
        transport = nil
        serverInfo = nil
        statusMessage = nil
    }

    /// Test di connessione con feedback dettagliato (latenza, versione, modalità).
    func testConnection() async -> String {
        isConnecting = true
        defer { isConnecting = false }

        let testTransport: any DatabaseTransport
        switch profile.mode {
        case .direct:
            testTransport = DirectTransport(profile: profile, password: secrets.databasePassword)
        case .ssh:
            testTransport = SSHTransport(
                profile: profile,
                databasePassword: secrets.databasePassword,
                sshPassword: secrets.sshPassword,
                sshPassphrase: secrets.sshPassphrase
            )
        case .bridge:
            testTransport = BridgeTransport(
                profile: profile,
                token: secrets.bridgeToken,
                hmacSecret: secrets.bridgeHMACSecret
            )
        }

        do {
            let info = try await testTransport.connect()
            let latency = try await testTransport.pingLatency()
            await testTransport.close()
            return String(
                format: "OK — %@ · versione %@ · latenza handshake %.2f ms · ping %.2f ms",
                profile.mode.displayName,
                info.version,
                info.latencyMS,
                latency
            )
        } catch {
            await testTransport.close()
            return "Errore: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    func requireTransport() throws -> any DatabaseTransport {
        guard let transport, transport.isConnected else { throw DBError.notConnected }
        return transport
    }
}
