//
//  DB_App.swift
//  DB+
//
//  Created by Alain Lima on 01/08/2026.
//

import SwiftUI

@main
struct DB_App: App {
    @State private var store = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView(store: store)
                .frame(minWidth: 1080, minHeight: 680)
        }
    }
}
