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

        // 差分ビューアウィンドウ
        WindowGroup(id: "diff-viewer", for: DiffViewerData.self) { $data in
            if let data = data {
                DiffViewerView(
                    context: DiffContext(
                        repository: data.repository,
                        commits: data.commits,
                        browseMode: data.browseMode
                    )
                )
            } else {
                Text("データがありません")
            }
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Diff Viewer Data

/// 差分ビューアに渡すデータ
struct DiffViewerData: Codable, Hashable {
    let repository: Repository
    let commits: [Commit]
    var browseMode: Bool = false  // true: ファイル閲覧モード（差分なし）
}
