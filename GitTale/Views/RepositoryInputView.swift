//
//  RepositoryInputView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

struct RepositoryInputView: View {
    @Environment(\.openSettings) private var openSettings
    @State private var repositories: [Repository] = []
    @State private var selectedRepository: Repository?
    @State private var newRepositoryURL: String = ""
    @State private var isCloning: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            // Sidebar: リポジトリ一覧
            List(selection: $selectedRepository) {
                Section("リポジトリ一覧") {
                    ForEach(repositories) { repo in
                        RepositoryRow(repository: repo)
                            .tag(repo)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: { selectedRepository = nil }) {
                        Image(systemName: "plus")
                    }
                    .help("新しいリポジトリを追加")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: { openSettings() }) {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.plain)
                    .help("設定")

                    Spacer()
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            // Detail: 選択中のリポジトリ or 新規追加フォーム
            if let repo = selectedRepository {
                RepositoryDetailView(repository: repo)
            } else {
                AddRepositoryView(
                    repositoryURL: $newRepositoryURL,
                    isCloning: $isCloning,
                    errorMessage: $errorMessage,
                    onClone: cloneRepository
                )
            }
        }
        .navigationTitle("GitTale")
        .task {
            await loadRepositories()
        }
    }

    private func loadRepositories() async {
        do {
            repositories = try await RepositoryStorage.shared.loadAll()
        } catch {
            print("Failed to load repositories: \(error)")
        }
    }

    private func cloneRepository() {
        guard !newRepositoryURL.isEmpty else { return }

        isCloning = true
        errorMessage = nil

        Task {
            do {
                // URLを解析してowner/nameを取得
                let (owner, name) = try await GitService.shared.parseRepositoryURL(newRepositoryURL)

                // 既に存在するか確認
                if await RepositoryStorage.shared.exists(owner: owner, name: name) {
                    await MainActor.run {
                        errorMessage = "このリポジトリは既にクローン済みです"
                        isCloning = false
                    }
                    return
                }

                // ディレクトリを作成
                let settings = AppSettings.shared
                try settings.ensureDirectoryStructureExists()
                try settings.ensureRepositoryDirectoryExists(owner: owner, name: name)

                // クローン先のパス
                let destination = settings.repositorySourceURL(owner: owner, name: name)

                // git clone実行
                try await GitService.shared.clone(url: newRepositoryURL, to: destination)

                // メタデータを保存
                let newRepo = Repository(owner: owner, name: name, url: newRepositoryURL)
                try await RepositoryStorage.shared.save(newRepo)

                // UIを更新
                await MainActor.run {
                    repositories.append(newRepo)
                    selectedRepository = newRepo
                    newRepositoryURL = ""
                    isCloning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCloning = false
                }
            }
        }
    }
}

// MARK: - Subviews

struct RepositoryRow: View {
    let repository: Repository

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(repository.displayName)
                    .font(.body)
                Text(repository.clonedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddRepositoryView: View {
    @Binding var repositoryURL: String
    @Binding var isCloning: Bool
    @Binding var errorMessage: String?
    let onClone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("新しいリポジトリを追加")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // URL Input
            VStack(spacing: 12) {
                TextField("https://github.com/user/repository.git", text: $repositoryURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                    .disabled(isCloning)

                Button(action: onClone) {
                    if isCloning {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Cloning...")
                        }
                        .frame(width: 120)
                    } else {
                        Text("Clone")
                            .frame(width: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(repositoryURL.isEmpty || isCloning)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Help
            Text("GitHub、GitLab等のリポジトリURLを入力してください")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RepositoryDetailView: View {
    let repository: Repository

    var body: some View {
        CommitTimelineView(repository: repository)
    }
}

#Preview {
    RepositoryInputView()
}
