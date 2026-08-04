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
    /// Default: disattivato (opt-in), così su dispositivi/simulatori senza
    /// biometria configurata l'app non si blocca all'avvio.
    static var requireBiometricLock: Bool {
        get { UserDefaults.standard.object(forKey: requireBiometricLockKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: requireBiometricLockKey) }
    }
}
