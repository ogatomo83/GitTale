//
//  RepositoryInputView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

/// 仮のリポジトリデータ（後でModelに移動）
struct Repository: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let clonedAt: Date?
}

struct RepositoryInputView: View {
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
    }

    private func cloneRepository() {
        guard !newRepositoryURL.isEmpty else { return }

        isCloning = true
        errorMessage = nil

        // TODO: Implement actual clone logic
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // 仮実装: リポジトリ名を抽出して一覧に追加
            let repoName = extractRepositoryName(from: newRepositoryURL)
            let newRepo = Repository(name: repoName, url: newRepositoryURL, clonedAt: Date())
            repositories.append(newRepo)
            selectedRepository = newRepo
            newRepositoryURL = ""
            isCloning = false
        }
    }

    private func extractRepositoryName(from url: String) -> String {
        // URLからリポジトリ名を抽出
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutGit = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed
        return withoutGit.components(separatedBy: "/").last ?? "Unknown"
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
                Text(repository.name)
                    .font(.body)
                if let date = repository.clonedAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(repository.name)
                .font(.title)
                .fontWeight(.bold)

            Text(repository.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()

            Divider()
                .padding(.horizontal, 40)

            Text("コミット履歴の表示は次のissueで実装予定です")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RepositoryInputView()
}
