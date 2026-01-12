//
//  CommitTimelineView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import SwiftUI

struct CommitTimelineView: View {
    @Environment(\.openWindow) private var openWindow
    let repository: Repository

    // SHAリスト（軽量）
    @State private var commitSHAs: [String] = []

    // 読み込み済みのコミット詳細（キャッシュ）
    @State private var commitCache: [String: Commit] = [:]

    // 表示用のコミット（最初のN件）
    @State private var displayedCommits: [Commit] = []

    @State private var progress: RepositoryProgress = RepositoryProgress()
    @State private var selectedCommits: Set<Commit> = []  // マルチ選択対応
    @State private var isLoading = true
    @State private var loadingMessage = "読み込み中..."
    @State private var errorMessage: String?
    @State private var isFetching = false

    private let batchSize = 50  // 一度に読み込む件数

    /// 現在のチェックアウトSHA（progressから取得）
    private var currentCheckoutSHA: String? {
        progress.currentCheckoutSHA
    }

    /// 選択されたコミット（古い順にソート）
    private var sortedSelectedCommits: [Commit] {
        selectedCommits.sorted { $0.date < $1.date }
    }

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
                        selectedCommits: $selectedCommits,
                        onToggle: toggleCommit,
                        onLoadMore: loadMoreCommits,
                        onOpenDiff: openDiffViewer,
                        onCheckout: checkoutCommit,
                        onBrowseFiles: browseCurrentFiles
                    )
                    .frame(minWidth: 300, maxWidth: 500)

                    Divider()

                    // Commit Detail / Selection Panel
                    CommitSelectionPanel(
                        selectedCommits: sortedSelectedCommits,
                        progress: progress,
                        currentCheckoutSHA: currentCheckoutSHA,
                        onToggle: toggleCommit,
                        onOpenDiff: openDiffViewer,
                        onBrowseFiles: browseCurrentFiles
                    )
                    .frame(maxWidth: .infinity)
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

    // MARK: - Diff Viewer

    private func openDiffViewer() {
        let commits = sortedSelectedCommits
        guard !commits.isEmpty, commits.count <= 2 else { return }

        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                // 新しい方のコミットにチェックアウト
                let targetSHA = commits.count == 1 ? commits[0].sha : commits[1].sha
                try await GitService.shared.checkout(sha: targetSHA, at: sourcePath)

                // 進捗にチェックアウト状態を保存
                await MainActor.run {
                    progress.setCheckout(targetSHA)
                }
                try await ProgressStorage.shared.save(progress, owner: repository.owner, name: repository.name)

                // 差分ビューアウィンドウを開く
                let data = DiffViewerData(repository: repository, commits: commits)
                openWindow(id: "diff-viewer", value: data)
            } catch {
                print("[CommitTimelineView] チェックアウトエラー: \(error)")
            }
        }
    }

    // MARK: - Checkout

    /// 特定のコミットにチェックアウト（ダブルクリック用）
    private func checkoutCommit(_ commit: Commit) {
        Task {
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                try await GitService.shared.checkout(sha: commit.sha, at: sourcePath)

                // 進捗にチェックアウト状態を保存
                await MainActor.run {
                    progress.setCheckout(commit.sha)
                }
                try await ProgressStorage.shared.save(progress, owner: repository.owner, name: repository.name)
                print("[CommitTimelineView] チェックアウト完了: \(commit.shortSHA)")
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

                // 進捗のチェックアウト状態をクリア
                await MainActor.run {
                    progress.setCheckout(nil)
                }
                try await ProgressStorage.shared.save(progress, owner: repository.owner, name: repository.name)
            } catch {
                print("[CommitTimelineView] 最新チェックアウトエラー: \(error)")
            }
        }
    }

    // MARK: - Browse Files

    /// ファイルを閲覧（チェックアウト中のSHAまたは最新コミット）
    private func browseCurrentFiles() {
        // チェックアウト中のSHAがあればそれを使う、なければ最新コミット
        let targetSHA = currentCheckoutSHA ?? commitSHAs.last

        guard let sha = targetSHA else { return }

        Task {
            // キャッシュにあればそのまま使う
            if let commit = commitCache[sha] {
                let data = DiffViewerData(repository: repository, commits: [commit], browseMode: true)
                openWindow(id: "diff-viewer", value: data)
                return
            }

            // キャッシュにない場合は読み込む
            let settings = AppSettings.shared
            let sourcePath = settings.repositorySourceURL(owner: repository.owner, name: repository.name)

            do {
                let commit = try await GitService.shared.getCommitDetail(sha: sha, at: sourcePath)
                await MainActor.run {
                    commitCache[sha] = commit
                }
                let data = DiffViewerData(repository: repository, commits: [commit], browseMode: true)
                openWindow(id: "diff-viewer", value: data)
            } catch {
                print("[CommitTimelineView] コミット読み込みエラー: \(error)")
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
                        }
                        print("[CommitTimelineView] \(newSHAs.count)件の新規コミットを取得")
                    } else {
                        print("[CommitTimelineView] 新しいコミットはありません")
                    }
                }

                // チェックアウト状態をクリアして保存
                await MainActor.run {
                    progress.setCheckout(nil)
                }
                try await ProgressStorage.shared.save(progress, owner: repository.owner, name: repository.name)

            } catch {
                print("[CommitTimelineView] フェッチエラー: \(error)")
            }

            await MainActor.run {
                isFetching = false
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
    @Binding var selectedCommits: Set<Commit>
    let onToggle: (Commit) -> Void
    let onLoadMore: () -> Void
    let onOpenDiff: () -> Void
    let onCheckout: (Commit) -> Void
    let onBrowseFiles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ファイル閲覧バー（常に表示）
            HStack {
                if let sha = currentCheckoutSHA {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text("チェックアウト中: \(sha.prefix(7))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("最新コミット")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onBrowseFiles) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("ファイルを見る")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(currentCheckoutSHA != nil ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))

            Divider()

            // 選択中の表示とボタン
            if !selectedCommits.isEmpty {
                HStack {
                    Text("\(selectedCommits.count)件選択中")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if selectedCommits.count <= 2 {
                        Button(action: onOpenDiff) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("差分を表示")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("選択解除") {
                        selectedCommits.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            List(selection: $selectedCommits) {
                ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                    CommitRowView(
                        index: index + 1,
                        commit: commit,
                        isChecked: progress.isChecked(commit.sha),
                        isSelected: selectedCommits.contains(commit),
                        isCheckedOut: currentCheckoutSHA == commit.sha,
                        onToggle: { onToggle(commit) }
                    )
                    .tag(commit)
                    .onTapGesture(count: 2) {
                        // ダブルクリックでチェックアウト
                        onCheckout(commit)
                    }
                    .onTapGesture(count: 1) {
                        // シングルクリックで選択
                        if selectedCommits.contains(commit) {
                            selectedCommits.remove(commit)
                        } else {
                            selectedCommits.insert(commit)
                        }
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
        }
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

// MARK: - Commit Selection Panel

struct CommitSelectionPanel: View {
    let selectedCommits: [Commit]  // 古い順にソート済み
    let progress: RepositoryProgress
    let currentCheckoutSHA: String?
    let onToggle: (Commit) -> Void
    let onOpenDiff: () -> Void
    let onBrowseFiles: () -> Void

    var body: some View {
        if selectedCommits.isEmpty {
            // 未選択時: ファイル閲覧を促す
            VStack(spacing: 16) {
                if currentCheckoutSHA != nil {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("コミットにチェックアウト中")
                        .font(.headline)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("ファイルを閲覧")
                        .font(.headline)
                }

                Text("現在のファイル状態を閲覧できます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: onBrowseFiles) {
                    HStack {
                        Image(systemName: "folder")
                        Text("ファイルを見る")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()
                    .padding(.vertical)

                Text("または左のリストからコミットを選択して\n差分を確認できます\nダブルクリックでチェックアウト")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else if selectedCommits.count == 1 {
            // 1件選択
            let commit = selectedCommits[0]
            VStack(spacing: 0) {
                CommitDetailPanel(
                    commit: commit,
                    isChecked: progress.isChecked(commit.sha),
                    onToggle: { onToggle(commit) }
                )

                Divider()

                // 差分を表示ボタン
                HStack {
                    Spacer()
                    Button(action: onOpenDiff) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("差分を表示")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .padding()
            }
        } else if selectedCommits.count == 2 {
            // 2件選択
            VStack(spacing: 16) {
                Text("2つのコミットを比較")
                    .font(.headline)

                // 古いコミット
                VStack(alignment: .leading, spacing: 4) {
                    Text("From (古い)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CommitSummaryRow(commit: selectedCommits[0])
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: "arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // 新しいコミット
                VStack(alignment: .leading, spacing: 4) {
                    Text("To (新しい)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CommitSummaryRow(commit: selectedCommits[1])
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                // 差分を表示ボタン
                Button(action: onOpenDiff) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("差分を表示")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        } else {
            // 3件以上選択
            ContentUnavailableView(
                "2つまで選択してください",
                systemImage: "exclamationmark.triangle",
                description: Text("\(selectedCommits.count)件選択中\n比較できるのは最大2つのコミットです")
            )
        }
    }
}

// MARK: - Commit Summary Row

struct CommitSummaryRow: View {
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.subject)
                .font(.body)
                .lineLimit(2)

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
