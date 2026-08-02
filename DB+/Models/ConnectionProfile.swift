//
//  ConnectionProfile.swift
//  DB+
//

import Foundation

/// Modalità di connessione supportate dall'app.
enum ConnectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case ssh
    case bridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct: return "Diretta"
        case .ssh: return "Tunnel SSH"
        case .bridge: return "Tunnel HTTPS (Bridge)"
        }
    }

    /// Etichetta compatta per i controlli segmentati (es. la Picker modalità).
    var shortDisplayName: String {
        switch self {
        case .direct: return "Diretta"
        case .ssh: return "SSH"
        case .bridge: return "Bridge"
        }
    }

    var symbolName: String {
        switch self {
        case .direct: return "network"
        case .ssh: return "terminal"
        case .bridge: return "globe"
        }
    }
}

/// Tipo di autenticazione SSH.
enum SSHAuthType: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case privateKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "Chiave privata"
        }
    }
}

/// Profilo di connessione. I segreti (password, token) NON sono conservati
/// qui: vengono salvati nel Keychain di sistema tramite `SecretStore`,
/// referenziati dall'id del profilo.
struct ConnectionProfile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()

    // Generali
    var name: String = ""
    var color: String = "blue"
    /// Mantiene attiva la connessione con ping periodici (keep-alive).
    var keepAlive: Bool = true

    // Endpoint MySQL/MariaDB
    var host: String = ""
    var port: Int = 3306
    var username: String = ""
    var defaultSchema: String = ""
    var useTLS: Bool = true
    var allowSelfSignedTLS: Bool = false

    // Modalità
    var mode: ConnectionMode = .direct

    // SSH
    var sshHost: String = ""
    var sshPort: Int = 22
    var sshUsername: String = ""
    var sshAuthType: SSHAuthType = .password
    var sshKeyPath: String = ""
    var sshUsePassphrase: Bool = false

    // Bridge HTTPS
    var bridgeURL: String = ""
    var bridgeUseHMAC: Bool = true

    var displayLabel: String {
        if name.isEmpty { return "Connessione senza nome" }
        return name
    }

    static func empty() -> ConnectionProfile {
        ConnectionProfile()
    }
}

// MARK: - Codable backward-compatible
//
// La decodifica usa `decodeIfPresent` con i valori di default per ogni
// campo: aggiungere una proprietà in una release futura non deve rendere
// illeggibili i profili già salvati (altrimenti ConnectionStore li azzera).
// Nota: l'init(from:) vive in un'estensione così l'init memberwise della
// struct resta disponibile.
extension ConnectionProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, keepAlive
        case host, port, username, defaultSchema, useTLS, allowSelfSignedTLS
        case mode
        case sshHost, sshPort, sshUsername, sshAuthType, sshKeyPath, sshUsePassphrase
        case bridgeURL, bridgeUseHMAC
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        keepAlive = try c.decodeIfPresent(Bool.self, forKey: .keepAlive) ?? true
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 3306
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        defaultSchema = try c.decodeIfPresent(String.self, forKey: .defaultSchema) ?? ""
        useTLS = try c.decodeIfPresent(Bool.self, forKey: .useTLS) ?? true
        allowSelfSignedTLS = try c.decodeIfPresent(Bool.self, forKey: .allowSelfSignedTLS) ?? false
        mode = try c.decodeIfPresent(ConnectionMode.self, forKey: .mode) ?? .direct
        sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUsername = try c.decodeIfPresent(String.self, forKey: .sshUsername) ?? ""
        sshAuthType = try c.decodeIfPresent(SSHAuthType.self, forKey: .sshAuthType) ?? .password
        sshKeyPath = try c.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
        sshUsePassphrase = try c.decodeIfPresent(Bool.self, forKey: .sshUsePassphrase) ?? false
        bridgeURL = try c.decodeIfPresent(String.self, forKey: .bridgeURL) ?? ""
        bridgeUseHMAC = try c.decodeIfPresent(Bool.self, forKey: .bridgeUseHMAC) ?? true
    }
}
