//
//  ConnectionStore.swift
//  DB+
//
//  Persistenza dei profili di connessione (solo metadati non sensibili)
//  in UserDefaults. I segreti restano nel Keychain.
//

import Foundation
import Observation

@Observable
final class ConnectionStore {
    var profiles: [ConnectionProfile] = []

    private static let storageKey = "connectionProfiles.v1"

    init() {
        load()
        if profiles.isEmpty {
            profiles = [
                ConnectionProfile(name: "Server locale", host: "127.0.0.1", port: 3306, username: "root")
            ]
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            profiles = []
            return
        }
        do {
            profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        } catch {
            profiles = []
        }
    }

    func persist() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Non bloccante.
        }
    }

    func upsert(_ profile: ConnectionProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    func remove(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        SecretStore.deleteAll(for: profile.id)
        persist()
    }

    func profile(id: UUID?) -> ConnectionProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }
}
