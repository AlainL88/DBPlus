//
//  SecretStore.swift
//  DB+
//
//  Wrapper sul Keychain di sistema (Security.framework).
//  I segreti (password, passphrase, token) non vengono mai scritti su disco
//  come testo in chiaro: solo nel Keychain cifrato del sistema.
//

import Foundation
import Security

enum SecretKind: String, Sendable {
    case databasePassword
    case sshPassword
    case sshPassphrase
    case bridgeToken
    case bridgeHMACSecret
}

enum SecretStore {
    private static let service = "com.alain.DB-.secrets"

    private static func accountKey(profileID: UUID, kind: SecretKind) -> String {
        "\(profileID.uuidString).\(kind.rawValue)"
    }

    @discardableResult
    static func save(_ secret: String, profileID: UUID, kind: SecretKind) -> Bool {
        let account = accountKey(profileID: profileID, kind: kind)
        let data = Data(secret.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attrs as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(profileID: UUID, kind: SecretKind) -> String? {
        let account = accountKey(profileID: profileID, kind: kind)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(profileID: UUID, kind: SecretKind) {
        let account = accountKey(profileID: profileID, kind: kind)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll(for profileID: UUID) {
        for kind in [SecretKind.databasePassword, .sshPassword, .sshPassphrase, .bridgeToken, .bridgeHMACSecret] {
            delete(profileID: profileID, kind: kind)
        }
    }
}
