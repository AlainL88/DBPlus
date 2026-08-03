//
//  DB_App.swift
//  DB+
//
//  Created by Alain Lima on 01/08/2026.
//

import SwiftUI
import FirebaseCore
import FirebaseCrashlytics

@main
struct DB_App: App {
    @State private var store = ConnectionStore()
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isUnlocked || !AppSettings.requireBiometricLock {
                    MainWindowView(store: store)
                        #if os(macOS)
                        .frame(minWidth: 1080, minHeight: 680)
                        #endif
                } else {
                    LockedView(onUnlock: { isUnlocked = true })
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Riblocca quando l'app va in background / viene nascosta.
                if phase == .background {
                    isUnlocked = false
                }
            }
        }
    }
}
