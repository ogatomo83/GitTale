//
//  SettingsView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var workingDirectoryInput: String = ""
    @State private var showDirectoryPicker = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Working Directory")
                        .font(.headline)

                    Text("リポジトリのクローン先ディレクトリを指定します")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("", text: $workingDirectoryInput, prompt: Text("/Users/.../.GitTale"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()

                        Button("選択...") {
                            showDirectoryPicker = true
                        }

                        Button("デフォルトに戻す") {
                            workingDirectoryInput = settings.defaultWorkingDirectory
                            settings.workingDirectory = workingDirectoryInput
                        }
                        .foregroundStyle(.secondary)
                    }

                    Text("現在: \(settings.workingDirectory)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
                .padding(.vertical, 8)
            } header: {
                Label("ストレージ", systemImage: "folder")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 200)
        .onAppear {
            workingDirectoryInput = settings.workingDirectory
        }
        .onChange(of: workingDirectoryInput) { _, newValue in
            settings.workingDirectory = newValue
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    workingDirectoryInput = url.path
                    settings.workingDirectory = url.path
                }
            case .failure(let error):
                print("Directory picker error: \(error)")
            }
        }
    }
}

#Preview {
    SettingsView()
}
