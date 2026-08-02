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

    init() {
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(store: store)
                #if os(macOS)
                .frame(minWidth: 1080, minHeight: 680)
                #endif
        }
    }
}
