//
//  CommitTimelineView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

struct CommitTimelineView: View {
    let repository: Repository

    // SHAリスト（軽量）
    @State private var commitSHAs: [String] = []

    // 読み込み済みのコミット詳細（キャッシュ）
    @State private var commitCache: [String: Commit] = [:]

    // 表示用のコミット（最初のN件）
    @State private var displayedCommits: [Commit] = []

    @State private var progress: RepositoryProgress = RepositoryProgress()
    @State private var selectedCommit: Commit?
    @State private var isLoading = true
    @State private var loadingMessage = "読み込み中..."
    @State private var errorMessage: String?
    @State private var currentCheckoutSHA: String?
    @State private var isFetching = false

    private let batchSize = 50  // 一度に読み込む件数

    var body: some View {
        VStack(spacing: 0) {
            // Progress Header
            ProgressHeaderView(
                checkedCount: progress.checkedCommitSHAs.count,
                totalCount: commitSHAs.count,
                isFetching: isFetching,
                onFetch: fetchLatestCommits,
                onCheckoutLatest: checkoutLatest
            )

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "エラー",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                HStack(spacing: 0) {
                    // Timeline List
                    TimelineListView(
                        commits: displayedCommits,
                        totalCount: commitSHAs.count,
                        progress: progress,
                        currentCheckoutSHA: currentCheckoutSHA,
                        selectedCommit: $selectedCommit,
                        onToggle: toggleCommit,
                        onLoadMore: loadMoreCommits,
                        onDoubleClick: checkoutCommit
                    )
                    .frame(minWidth: 300, maxWidth: 500)

                    Divider()

                    // Commit Detail
                    if let commit = selectedCommit {
                        CommitDetailPanel(
                            commit: commit,
                            isChecked: progress.isChecked(commit.sha),
                            onToggle: { toggleCommit(commit) }
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView(
                            "コミットを選択",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("左のリストからコミットを選択してください")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            // Step 1: キャッシュからSHAリストを読み込み（または新規取得）
            loadingMessage = "コミット履歴を読み込み中..."
            commitSHAs = try await loadOrFetchCommitSHAs(sourcePath: sourcePath)
            print("[CommitTimelineView] SHAリスト準備完了: \(commitSHAs.count)件")

            // Step 2: 進捗を読み込み
            loadingMessage = "進捗を読み込み中..."
            progress = try await ProgressStorage.shared.load(owner: repository.owner, name: repository.name)
            print("[CommitTimelineView] 進捗読み込み完了: \(progress.checkedCommitSHAs.count)件確認済み")

            // Step 3: 最初のバッチを読み込み
            loadingMessage = "コミット詳細を読み込み中..."
            await loadInitialBatch(sourcePath: sourcePath)

        } catch {
            print("[CommitTimelineView] エラー: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// キャッシュからSHAリストを読み込み、なければ取得してキャッシュに保存
    private func loadOrFetchCommitSHAs(sourcePath: URL) async throws -> [String] {
        // キャッシュを確認
        if let cache = try await CommitStorage.shared.loadCache(owner: repository.owner, name: repository.name) {
            print("[CommitTimelineView] キャッシュから\(cache.shas.count)件読み込み")

            // 差分を確認（新しいコミットがあるか）
            if let lastSHA = cache.shas.last {
                let newSHAs = try await GitService.shared.getNewCommitSHAs(since: lastSHA, at: sourcePath)

                if !newSHAs.isEmpty {
                    print("[CommitTimelineView] \(newSHAs.count)件の新規コミットを発見")
                    // キャッシュを更新
                    try await CommitStorage.shared.appendToCache(newSHAs: newSHAs, owner: repository.owner, name: repository.name)
                    return cache.shas + newSHAs
                }
            }

            return cache.shas
        }

        // キャッシュがない場合は全件のSHAリストを取得（古い順）
        print("[CommitTimelineView] キャッシュなし、全SHAリストを取得中...")
        let shas = try await GitService.shared.getCommitSHAs(at: sourcePath)
        print("[CommitTimelineView] \(shas.count)件のSHAを取得")

        // キャッシュに保存
        let cache = CommitCache(shas: shas)
        try await CommitStorage.shared.saveCache(cache, owner: repository.owner, name: repository.name)

        return shas
    }

    private func loadInitialBatch(sourcePath: URL) async {
        let initialSHAs = Array(commitSHAs.prefix(batchSize))
        guard !initialSHAs.isEmpty else { return }

        print("[CommitTimelineView] 最初の\(initialSHAs.count)件の詳細を読み込み中...")

        do {
            let commits = try await GitService.shared.getCommitDetails(shas: initialSHAs, at: sourcePath)
            for commit in commits {
                commitCache[commit.sha] = commit
            }
            displayedCommits = commits
            print("[CommitTimelineView] 最初のバッチ読み込み完了")
        } catch {
            print("[CommitTimelineView] バッチ読み込みエラー: \(error)")
        }
    }

    private func loadMoreCommits() {
        let currentCount = displayedCommits.count

        // キャッシュにある分を表示
        if currentCount < commitSHAs.count {
            loadMoreFromCache()
            return
        }

        // キャッシュを超えた場合は新しいSHAを取得
        fetchMoreCommitSHAs()
    }

    private func loadMoreFromCache() {
        let currentCount = displayedCommits.count
        let nextSHAs = Array(commitSHAs[currentCount..<min(currentCount + batchSize, commitSHAs.count)])
        guard !nextSHAs.isEmpty else { return }

        print("[CommitTimelineView] キャッシュから追加\(nextSHAs.count)件を読み込み中...")

        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                let commits = try await GitService.shared.getCommitDetails(shas: nextSHAs, at: sourcePath)
                await MainActor.run {
                    for commit in commits {
                        commitCache[commit.sha] = commit
                    }
                    displayedCommits.append(contentsOf: commits)
                }
                print("[CommitTimelineView] 追加バッチ読み込み完了: 合計\(displayedCommits.count)件")
            } catch {
                print("[CommitTimelineView] 追加バッチエラー: \(error)")
            }
        }
    }

    private func fetchMoreCommitSHAs() {
        guard let lastSHA = commitSHAs.last else { return }

        print("[CommitTimelineView] 新しいコミットを取得中...")

        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                // 次のN件を取得
                let newSHAs = try await GitService.shared.getNewCommitSHAs(since: lastSHA, at: sourcePath)
                let limitedSHAs = Array(newSHAs.prefix(batchSize))

                if !limitedSHAs.isEmpty {
                    // キャッシュに追加
                    try await CommitStorage.shared.appendToCache(newSHAs: limitedSHAs, owner: repository.owner, name: repository.name)

                    await MainActor.run {
                        commitSHAs.append(contentsOf: limitedSHAs)
                    }

                    // 詳細を読み込み
                    let commits = try await GitService.shared.getCommitDetails(shas: limitedSHAs, at: sourcePath)
                    await MainActor.run {
                        for commit in commits {
                            commitCache[commit.sha] = commit
                        }
                        displayedCommits.append(contentsOf: commits)
                    }
                    print("[CommitTimelineView] 新規\(limitedSHAs.count)件を追加: 合計\(displayedCommits.count)件")
                } else {
                    print("[CommitTimelineView] 新しいコミットはありません")
                }
            } catch {
                print("[CommitTimelineView] 新規コミット取得エラー: \(error)")
            }
        }
    }

    private func toggleCommit(_ commit: Commit) {
        progress.toggle(commit.sha)

        Task {
            do {
                try await ProgressStorage.shared.save(progress, owner: repository.owner, name: repository.name)
            } catch {
                print("[CommitTimelineView] 進捗保存エラー: \(error)")
            }
        }
    }

    // MARK: - Checkout

    private func checkoutCommit(_ commit: Commit) {
        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                try await GitService.shared.checkout(sha: commit.sha, at: sourcePath)
                await MainActor.run {
                    currentCheckoutSHA = commit.sha
                }
            } catch {
                print("[CommitTimelineView] チェックアウトエラー: \(error)")
            }
        }
    }

    private func checkoutLatest() {
        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                try await GitService.shared.checkoutDefaultBranch(at: sourcePath)
                await MainActor.run {
                    currentCheckoutSHA = nil
                }
            } catch {
                print("[CommitTimelineView] 最新チェックアウトエラー: \(error)")
            }
        }
    }

    // MARK: - Fetch

    private func fetchLatestCommits() {
        guard !isFetching else { return }

        Task {
            await MainActor.run { isFetching = true }

            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                // リモートからfetch
                try await GitService.shared.fetch(at: sourcePath)

                // デフォルトブランチに戻してからpull
                try await GitService.shared.checkoutDefaultBranch(at: sourcePath)
                try await GitService.shared.pull(at: sourcePath)

                // 新しいコミットを確認
                if let lastSHA = commitSHAs.last {
                    let newSHAs = try await GitService.shared.getNewCommitSHAs(since: lastSHA, at: sourcePath)

                    if !newSHAs.isEmpty {
                        // キャッシュに追加
                        try await CommitStorage.shared.appendToCache(newSHAs: newSHAs, owner: repository.owner, name: repository.name)

                        await MainActor.run {
                            commitSHAs.append(contentsOf: newSHAs)
                            currentCheckoutSHA = nil
                        }
                        print("[CommitTimelineView] \(newSHAs.count)件の新規コミットを取得")
                    } else {
                        print("[CommitTimelineView] 新しいコミットはありません")
                    }
                }
            } catch {
                print("[CommitTimelineView] フェッチエラー: \(error)")
            }

            await MainActor.run {
                isFetching = false
                currentCheckoutSHA = nil
            }
        }
    }
}

// MARK: - Progress Header

struct ProgressHeaderView: View {
    let checkedCount: Int
    let totalCount: Int
    let isFetching: Bool
    let onFetch: () -> Void
    let onCheckoutLatest: () -> Void

    private var percentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(checkedCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("進捗")
                    .font(.headline)

                Spacer()

                // 最新コミットを取得ボタン
                Button(action: onFetch) {
                    if isFetching {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFetching)
                .help("最新コミットを取得")

                // 最新にチェックアウトボタン
                Button(action: onCheckoutLatest) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .help("最新のコミットにチェックアウト")
            }

            HStack {
                Text("\(checkedCount) / \(totalCount) コミット確認済み")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(percentage * 100))% 完了")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ProgressView(value: percentage)
                .progressViewStyle(.linear)
        }
        .padding()
    }
}

// MARK: - Timeline List

struct TimelineListView: View {
    let commits: [Commit]
    let totalCount: Int
    let progress: RepositoryProgress
    let currentCheckoutSHA: String?
    @Binding var selectedCommit: Commit?
    let onToggle: (Commit) -> Void
    let onLoadMore: () -> Void
    let onDoubleClick: (Commit) -> Void

    var body: some View {
        List(selection: $selectedCommit) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                CommitRowView(
                    index: index + 1,
                    commit: commit,
                    isChecked: progress.isChecked(commit.sha),
                    isSelected: selectedCommit?.sha == commit.sha,
                    isCheckedOut: currentCheckoutSHA == commit.sha,
                    onToggle: { onToggle(commit) }
                )
                .tag(commit)
                .onTapGesture(count: 2) {
                    onDoubleClick(commit)
                }
                .onTapGesture(count: 1) {
                    selectedCommit = commit
                }
            }

            // Load More Button
            if commits.count < totalCount {
                HStack {
                    Spacer()
                    Button(action: onLoadMore) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("さらに読み込む (\(commits.count)/\(totalCount))")
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Commit Row

struct CommitRowView: View {
    let index: Int
    let commit: Commit
    let isChecked: Bool
    let isSelected: Bool
    let isCheckedOut: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            ZStack {
                Circle()
                    .fill(isCheckedOut ? Color.blue : (isChecked ? Color.green : Color.secondary.opacity(0.3)))
                    .frame(width: 28, height: 28)

                if isCheckedOut {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28)

            // Commit info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(commit.subject)
                        .font(.body)
                        .lineLimit(1)

                    if isCheckedOut {
                        Text("HEAD")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 8) {
                    Text(commit.shortSHA)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)

                    Text(commit.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(commit.date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Check button
            Button(action: onToggle) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Commit Detail Panel

struct CommitDetailPanel: View {
    let commit: Commit
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(commit.subject)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        Button(action: onToggle) {
                            HStack {
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                Text(isChecked ? "確認済み" : "未確認")
                            }
                            .foregroundStyle(isChecked ? .green : .secondary)
                        }
                        .buttonStyle(.bordered)
                    }

                    if commit.message.contains("\n") {
                        Text(commit.message.components(separatedBy: "\n").dropFirst().joined(separator: "\n"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    MetadataRow(label: "SHA", value: commit.sha)
                    MetadataRow(label: "Author", value: "\(commit.author) <\(commit.email)>")
                    MetadataRow(label: "Date", value: commit.date.formatted(date: .long, time: .shortened))

                    if !commit.parentSHAs.isEmpty {
                        MetadataRow(label: "Parents", value: commit.parentSHAs.joined(separator: ", "))
                    }

                    if commit.isMergeCommit {
                        HStack {
                            Image(systemName: "arrow.triangle.merge")
                            Text("マージコミット")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body)
                .monospaced()
                .textSelection(.enabled)
        }
    }
}

#Preview {
    CommitTimelineView(
        repository: Repository(
            owner: "rails",
            name: "rails",
            url: "https://github.com/rails/rails.git"
        )
    )
}
