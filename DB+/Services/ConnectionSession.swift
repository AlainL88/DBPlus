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
    /// Vero quando la connessione è stata persa (server, background, rete).
    var connectionLost = false
    private var keepAliveTask: Task<Void, Never>?
    private let keepAliveInterval: TimeInterval = 30

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
        connectionLost = false
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
            if profile.keepAlive {
                startKeepAlive()
            }
        } catch {
            errorMessage = error.localizedDescription
            await newTransport.close()
        }
    }

    func disconnect() async {
        stopKeepAlive()
        await transport?.close()
        transport = nil
        serverInfo = nil
        statusMessage = nil
        connectionLost = false
    }

    /// Test di connessione con feedback dettagliato (latenza, versione, modalità).
    /// I parametri espliciti sovrascrivono i segreti del Keychain (usati
    /// dall'editor di connessione per testare credenziali non ancora salvate).
    func testConnection(databasePassword: String? = nil,
                        sshPassword: String? = nil,
                        sshPassphrase: String? = nil,
                        bridgeToken: String? = nil,
                        bridgeHMACSecret: String? = nil) async -> String {
        isConnecting = true
        defer { isConnecting = false }
        let startAll = DispatchTime.now()

        // Segreti effettivi: quelli espliciti oppure quelli caricati dal Keychain.
        let dbPassword = databasePassword ?? secrets.databasePassword
        let sshPwd = sshPassword ?? secrets.sshPassword
        let sshPhrase = sshPassphrase ?? secrets.sshPassphrase
        let token = bridgeToken ?? secrets.bridgeToken
        let hmac = bridgeHMACSecret ?? secrets.bridgeHMACSecret

        DebugLog.shared.log("[DB+DEBUG] testConnection() inizio — mode=\(profile.mode.displayName) host=\(profile.host):\(profile.port) useTLS=\(profile.useTLS) ssh=\(profile.sshHost):\(profile.sshPort) auth=\(profile.sshAuthType.displayName)")

        // Watchdog: se il test resta bloccato, logga ogni 10s finché non finisce.
        let watchdog = Task {
            var elapsed = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                elapsed += 10
                DebugLog.shared.log("[DB+DEBUG] ⚠️ watchdog: test ancora in corso dopo \(elapsed)s — probabile blocco in un await")
            }
        }
        defer { watchdog.cancel() }

        let testTransport: any DatabaseTransport
        switch profile.mode {
        case .direct:
            testTransport = DirectTransport(profile: profile, password: dbPassword)
        case .ssh:
            testTransport = SSHTransport(
                profile: profile,
                databasePassword: dbPassword,
                sshPassword: sshPwd,
                sshPassphrase: sshPhrase
            )
        case .bridge:
            testTransport = BridgeTransport(
                profile: profile,
                token: token,
                hmacSecret: hmac
            )
        }
        DebugLog.shared.log("[DB+DEBUG] testConnection() transport creato: \(type(of: testTransport))")

        do {
            DebugLog.shared.log("[DB+DEBUG] testConnection() connect(): inizio")
            let info = try await testTransport.connect()
            DebugLog.shared.log("[DB+DEBUG] testConnection() connect(): OK — version=\(info.version) latency=\(info.latencyMS) ms")
            DebugLog.shared.log("[DB+DEBUG] testConnection() pingLatency(): inizio")
            let latency = try await testTransport.pingLatency()
            DebugLog.shared.log("[DB+DEBUG] testConnection() pingLatency(): OK — \(latency) ms")
            DebugLog.shared.log("[DB+DEBUG] testConnection() close(): inizio")
            await testTransport.close()
            DebugLog.shared.log("[DB+DEBUG] testConnection() close(): OK")
            let totalMS = Double(DispatchTime.now().uptimeNanoseconds - startAll.uptimeNanoseconds) / 1_000_000
            DebugLog.shared.log("[DB+DEBUG] testConnection() FINE OK — totale \(totalMS) ms")
            return String(
                format: "OK — %@ · versione %@ · latenza handshake %.2f ms · ping %.2f ms",
                profile.mode.displayName,
                info.version,
                info.latencyMS,
                latency
            )
        } catch {
            DebugLog.shared.log("[DB+DEBUG] testConnection() ERRORE: \(error.localizedDescription)")
            await testTransport.close()
            DebugLog.shared.log("[DB+DEBUG] testConnection() close() dopo errore: OK")
            return "Errore: \(error.localizedDescription)"
        }
    }

    // MARK: - Keep-alive

    /// Esegue un ping periodico per mantenere attiva la connessione.
    /// Se un ping fallisce, segnala la perdita della connessione.
    private func startKeepAlive() {
        stopKeepAlive()
        let interval = keepAliveInterval
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard let transport = self.transport, transport.isConnected else { return }
                do {
                    try await transport.pingLatency()
                } catch {
                    self.connectionLost = true
                    self.stopKeepAlive()
                }
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
    }

    // MARK: - Helpers

    func requireTransport() throws -> any DatabaseTransport {
        guard let transport, transport.isConnected else { throw DBError.notConnected }
        return transport
    }
}
