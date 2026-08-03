//
//  AppSettings.swift
//  DB+
//
//  Preferenze dell'app persistite su UserDefaults.
//

import Foundation

enum AppSettings {
    private static let requireBiometricLockKey = "requireBiometricLock"

    /// Richiede l'autenticazione Face ID / Touch ID all'avvio e in background.
    /// Default: attivo.
    static var requireBiometricLock: Bool {
        get { UserDefaults.standard.object(forKey: requireBiometricLockKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: requireBiometricLockKey) }
    }
}
