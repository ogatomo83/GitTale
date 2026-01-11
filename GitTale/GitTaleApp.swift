//
//  GitTaleApp.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

@main
struct GitTaleApp: App {
    init() {
        AppSettings.shared.resetInvalidPathIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsView()
        }
    }
}
