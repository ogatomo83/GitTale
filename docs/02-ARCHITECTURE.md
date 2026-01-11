# GitTale - 技術アーキテクチャ設計書

## 1. アーキテクチャ概要

### 1.1 設計原則

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitTale Architecture                         │
│                                                                 │
│   "Git is the database. We just read and cache AI summaries."  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**3つの原則:**
1. **Gitが真実** - コミット情報は毎回Gitから取得
2. **DBレス** - SwiftData/SQLite不使用。JSONファイルキャッシュのみ
3. **読み取り専用** - リポジトリを変更しない（.gittaleディレクトリ除く）

### 1.2 システム構成図

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              GitTale                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Presentation Layer                           │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐    │   │
│  │  │ SidebarView│ │TimelineView│ │ DetailView │ │SettingsView│    │   │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Application Layer                            │   │
│  │  ┌────────────────┐ ┌────────────────┐ ┌────────────────────┐   │   │
│  │  │ GitRepository  │ │ SummaryEngine  │ │ GroupingStrategy   │   │   │
│  │  │ (Actor)        │ │ (Actor)        │ │                    │   │   │
│  │  └────────────────┘ └────────────────┘ └────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                          │                   │                          │
│                          ▼                   ▼                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Infrastructure Layer                         │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐    │   │
│  │  │ GitCLI     │ │ AIProvider │ │ FileCache  │ │ Keychain   │    │   │
│  │  │            │ │ (Protocol) │ │ (.gittale/)│ │            │    │   │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│            │                │                │                          │
│            ▼                ▼                ▼                          │
│       ┌─────────┐    ┌───────────┐    ┌─────────────┐                  │
│       │  .git/  │    │  AI APIs  │    │  .gittale/  │                  │
│       │ (読取)  │    │           │    │  cache/     │                  │
│       └─────────┘    └───────────┘    └─────────────┘                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Git操作パイプライン

### 2.1 GitCLI - コマンド実行ラッパー

```swift
/// Git CLIラッパー
actor GitCLI {
    private let repositoryPath: URL

    init(repositoryPath: URL) {
        self.repositoryPath = repositoryPath
    }

    /// Gitコマンド実行
    func execute(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryPath

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed(arguments.joined(separator: " "), errorMessage)
        }

        return output
    }
}

enum GitError: LocalizedError {
    case notARepository
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "Not a Git repository"
        case .commandFailed(let cmd, let msg):
            return "git \(cmd): \(msg)"
        }
    }
}
```

### 2.2 GitRepository - メインアクター

```swift
/// リポジトリ操作アクター
actor GitRepository {
    private let git: GitCLI
    private let cache: FileCache
    let path: URL

    init(path: URL) throws {
        // .git ディレクトリ確認
        let gitDir = path.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            throw GitError.notARepository
        }

        self.path = path
        self.git = GitCLI(repositoryPath: path)
        self.cache = FileCache(repositoryPath: path)
    }

    // MARK: - Commit Operations

    /// 全コミット取得（最古から最新順）
    func getAllCommits() async throws -> [Commit] {
        let format = "%H|%an|%ae|%aI|%s|%P"
        let output = try await git.execute([
            "log", "--reverse", "--all", "--format=\(format)"
        ])

        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap(parseCommit)
    }

    /// 最初のコミット取得
    func getFirstCommit() async throws -> Commit? {
        let output = try await git.execute([
            "log", "--reverse", "--format=%H|%an|%ae|%aI|%s|%P", "-1"
        ])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? nil : parseCommit(output)
    }

    /// 特定のコミット以降を取得
    func getCommits(since sha: String) async throws -> [Commit] {
        let output = try await git.execute([
            "log", "--reverse", "--format=%H|%an|%ae|%aI|%s|%P", "\(sha)..HEAD"
        ])

        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap(parseCommit)
    }

    // MARK: - Diff Operations

    /// Diff統計取得
    func getDiffStats(for sha: String) async throws -> DiffStats {
        // --stat で統計取得
        let statOutput = try await git.execute([
            "diff", "--stat", "--stat-width=300", "\(sha)^...\(sha)"
        ])

        // --name-status で変更種別取得
        let nameStatusOutput = try await git.execute([
            "diff", "--name-status", "\(sha)^...\(sha)"
        ])

        return parseDiffStats(stat: statOutput, nameStatus: nameStatusOutput)
    }

    // MARK: - Tag Operations

    /// 全タグ取得
    func getAllTags() async throws -> [Tag] {
        let output = try await git.execute([
            "tag", "-l", "--format=%(refname:short)|%(objectname:short)|%(*objectname:short)|%(creatordate:iso-strict)"
        ])

        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap(parseTag)
            .sorted { $0.date < $1.date }
    }

    // MARK: - Checkout Operations

    /// 特定のコミットをcheckout（detached HEAD）
    func checkout(sha: String) async throws {
        _ = try await git.execute(["checkout", sha])
    }

    /// 元のブランチに戻る
    func checkoutOriginal(branch: String) async throws {
        _ = try await git.execute(["checkout", branch])
    }

    /// 現在のブランチ名取得
    func getCurrentBranch() async throws -> String {
        let output = try await git.execute(["branch", "--show-current"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing Helpers

    private func parseCommit(_ line: String) -> Commit? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 5 else { return nil }

        let parentSHAs = parts.count > 5
            ? parts[5].components(separatedBy: " ").filter { !$0.isEmpty }
            : []

        return Commit(
            sha: parts[0],
            author: parts[1],
            email: parts[2],
            date: ISO8601DateFormatter().date(from: parts[3]) ?? Date(),
            message: parts[4],
            parentSHAs: parentSHAs
        )
    }

    private func parseDiffStats(stat: String, nameStatus: String) -> DiffStats {
        var additions = 0
        var deletions = 0
        var files: [FileChange] = []

        // Parse --stat output for additions/deletions
        let lines = stat.components(separatedBy: "\n")
        for line in lines {
            if line.contains("insertion") || line.contains("deletion") {
                let numbers = line.components(separatedBy: " ")
                    .compactMap { Int($0) }
                if numbers.count >= 1 { additions = numbers.count > 1 ? numbers[0] : 0 }
                if numbers.count >= 2 { deletions = numbers[1] }
            }
        }

        // Parse --name-status for file changes
        for line in nameStatus.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }

            let status: FileChange.Status
            switch parts[0].first {
            case "A": status = .added
            case "M": status = .modified
            case "D": status = .deleted
            case "R": status = .renamed
            default: status = .modified
            }

            files.append(FileChange(path: parts[1], status: status))
        }

        return DiffStats(
            additions: additions,
            deletions: deletions,
            filesChanged: files
        )
    }

    private func parseTag(_ line: String) -> Tag? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 3 else { return nil }

        let sha = parts[2].isEmpty ? parts[1] : parts[2] // annotated vs lightweight
        let dateStr = parts.count > 3 ? parts[3] : ""

        return Tag(
            name: parts[0],
            commitSHA: sha,
            date: ISO8601DateFormatter().date(from: dateStr) ?? Date()
        )
    }
}
```

---

## 3. AI要約エンジン

### 3.1 SummaryEngine - 要約生成アクター

```swift
/// 要約生成エンジン
actor SummaryEngine {
    private let aiProvider: AIProvider
    private let cache: FileCache
    private let promptGenerator = PromptGenerator()

    init(aiProvider: AIProvider, cache: FileCache) {
        self.aiProvider = aiProvider
        self.cache = cache
    }

    // MARK: - Commit Summary

    /// 単一コミットの要約（キャッシュ付き）
    func summarizeCommit(_ commit: Commit, diff: DiffStats) async throws -> CommitSummary {
        // キャッシュチェック
        if let cached: CommitSummary = try? await cache.load(
            type: .commit,
            id: commit.sha
        ) {
            return cached
        }

        // AI生成
        let prompt = promptGenerator.commitPrompt(commit: commit, diff: diff)
        let response = try await aiProvider.complete(prompt: prompt)
        let summary = try parseCommitSummary(response, sha: commit.sha)

        // キャッシュ保存
        try await cache.save(summary, type: .commit, id: commit.sha)

        return summary
    }

    /// バッチでコミット要約（並行処理）
    func summarizeCommits(
        _ commits: [(Commit, DiffStats)],
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [String: CommitSummary] {
        var results: [String: CommitSummary] = [:]
        let total = commits.count

        // 同時実行数を制限（API rate limit対策）
        let batchSize = 5

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(commits[batchStart..<batchEnd])

            try await withThrowingTaskGroup(of: (String, CommitSummary).self) { group in
                for (commit, diff) in batch {
                    group.addTask {
                        let summary = try await self.summarizeCommit(commit, diff: diff)
                        return (commit.sha, summary)
                    }
                }

                for try await (sha, summary) in group {
                    results[sha] = summary
                }
            }

            progress(batchEnd, total)
        }

        return results
    }

    // MARK: - Group Summary

    /// グループ要約生成
    func summarizeGroup(
        _ group: CommitGroup,
        commitSummaries: [CommitSummary]
    ) async throws -> GroupSummary {
        // キャッシュキー: グループの最新コミットSHA
        let cacheId = group.id

        if let cached: GroupSummary = try? await cache.load(type: .group, id: cacheId) {
            return cached
        }

        let prompt = promptGenerator.groupPrompt(
            group: group,
            summaries: commitSummaries
        )
        let response = try await aiProvider.complete(prompt: prompt)
        let summary = try parseGroupSummary(response, groupId: cacheId)

        try await cache.save(summary, type: .group, id: cacheId)

        return summary
    }

    // MARK: - Version Summary

    /// バージョン要約生成
    func summarizeVersion(
        tag: Tag,
        groups: [GroupSummary]
    ) async throws -> VersionSummary {
        if let cached: VersionSummary = try? await cache.load(
            type: .version,
            id: tag.name
        ) {
            return cached
        }

        let prompt = promptGenerator.versionPrompt(tag: tag, groups: groups)
        let response = try await aiProvider.complete(prompt: prompt)
        let summary = try parseVersionSummary(response, version: tag.name)

        try await cache.save(summary, type: .version, id: tag.name)

        return summary
    }

    // MARK: - Project Story

    /// プロジェクトストーリー生成
    func generateProjectStory(
        versions: [VersionSummary]
    ) async throws -> ProjectStory {
        if let cached: ProjectStory = try? await cache.load(
            type: .story,
            id: "main"
        ) {
            return cached
        }

        let prompt = promptGenerator.projectStoryPrompt(versions: versions)
        let response = try await aiProvider.complete(prompt: prompt)
        let story = try parseProjectStory(response)

        try await cache.save(story, type: .story, id: "main")

        return story
    }

    // MARK: - Parsing

    private func parseCommitSummary(_ json: String, sha: String) throws -> CommitSummary {
        let data = json.data(using: .utf8) ?? Data()
        let decoded = try JSONDecoder().decode(CommitSummaryResponse.self, from: data)

        return CommitSummary(
            sha: sha,
            summary: decoded.summary,
            category: ChangeCategory(rawValue: decoded.category) ?? .change,
            impact: Impact(rawValue: decoded.impact) ?? .low,
            keywords: decoded.keywords
        )
    }

    // ... 他のパース関数
}
```

### 3.2 AIProvider Protocol

```swift
/// AIプロバイダープロトコル
protocol AIProvider: Sendable {
    var name: String { get }
    func complete(prompt: String) async throws -> String
    func isAvailable() async -> Bool
}

/// OpenAI実装
final class OpenAIProvider: AIProvider, @unchecked Sendable {
    let name = "OpenAI"
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4-turbo-preview") {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    func isAvailable() async -> Bool {
        !apiKey.isEmpty
    }
}

/// Ollama実装（ローカルLLM）
final class OllamaProvider: AIProvider, @unchecked Sendable {
    let name = "Ollama"
    private let host: String
    private let port: Int
    private let model: String

    init(host: String = "localhost", port: Int = 11434, model: String = "llama3") {
        self.host = host
        self.port = port
        self.model = model
    }

    func complete(prompt: String) async throws -> String {
        let url = URL(string: "http://\(host):\(port)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable { let response: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.response
    }

    func isAvailable() async -> Bool {
        let url = URL(string: "http://\(host):\(port)/api/tags")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

---

## 4. ファイルキャッシュ

### 4.1 FileCache - JSONベースキャッシュ

```swift
/// ファイルベースキャッシュ
actor FileCache {
    private let baseDir: URL

    enum CacheType: String {
        case commit = "commits"
        case group = "groups"
        case version = "versions"
        case story = "story"
    }

    init(repositoryPath: URL) {
        self.baseDir = repositoryPath
            .appendingPathComponent(".gittale")
            .appendingPathComponent("cache")
    }

    // MARK: - Setup

    /// キャッシュディレクトリの初期化
    func setup() throws {
        let fm = FileManager.default

        // .gittale ディレクトリ作成
        let gittaleDir = baseDir.deletingLastPathComponent()
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // 各サブディレクトリ作成
        for type in [CacheType.commit, .group, .version] {
            let typeDir = baseDir.appendingPathComponent(type.rawValue)
            try fm.createDirectory(at: typeDir, withIntermediateDirectories: true)
        }

        // .gitignore 作成
        let gitignorePath = gittaleDir.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitignorePath.path) {
            let content = "# GitTale cache - do not commit\n**\n"
            try content.write(to: gitignorePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Load

    func load<T: Decodable>(type: CacheType, id: String) async throws -> T {
        let path = cachePath(type: type, id: id)
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func exists(type: CacheType, id: String) -> Bool {
        FileManager.default.fileExists(atPath: cachePath(type: type, id: id).path)
    }

    // MARK: - Save

    func save<T: Encodable>(_ value: T, type: CacheType, id: String) async throws {
        let path = cachePath(type: type, id: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: path)
    }

    // MARK: - Delete

    func delete(type: CacheType, id: String) throws {
        let path = cachePath(type: type, id: id)
        try FileManager.default.removeItem(at: path)
    }

    func deleteAll(type: CacheType) throws {
        let dir = baseDir.appendingPathComponent(type.rawValue)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// グループ/バージョンキャッシュを無効化（新規コミット追加時）
    func invalidateGroupCaches() throws {
        try deleteAll(type: .group)
        try deleteAll(type: .version)
        try FileManager.default.removeItem(
            at: baseDir.appendingPathComponent("story.json")
        )
    }

    // MARK: - Helpers

    private func cachePath(type: CacheType, id: String) -> URL {
        switch type {
        case .story:
            return baseDir.appendingPathComponent("story.json")
        default:
            return baseDir
                .appendingPathComponent(type.rawValue)
                .appendingPathComponent("\(id).json")
        }
    }
}
```

---

## 5. グルーピング戦略

### 5.1 GroupingStrategy Protocol

```swift
/// グルーピング戦略プロトコル
protocol GroupingStrategy {
    func group(commits: [Commit], tags: [Tag]) -> [CommitGroup]
}

/// タグベースグルーピング
struct TagBasedGrouping: GroupingStrategy {
    func group(commits: [Commit], tags: [Tag]) -> [CommitGroup] {
        guard !tags.isEmpty else {
            return [CommitGroup(
                id: "all",
                name: "All Commits",
                commits: commits,
                startDate: commits.first?.date ?? Date(),
                endDate: commits.last?.date ?? Date()
            )]
        }

        var groups: [CommitGroup] = []
        let sortedTags = tags.sorted { $0.date < $1.date }

        for i in 0..<sortedTags.count {
            let tag = sortedTags[i]
            let previousDate = i > 0 ? sortedTags[i-1].date : Date.distantPast

            let groupCommits = commits.filter { commit in
                commit.date > previousDate && commit.date <= tag.date
            }

            if !groupCommits.isEmpty {
                groups.append(CommitGroup(
                    id: tag.name,
                    name: i > 0 ? "\(sortedTags[i-1].name) → \(tag.name)" : "Initial → \(tag.name)",
                    commits: groupCommits,
                    startDate: previousDate,
                    endDate: tag.date,
                    tag: tag
                ))
            }
        }

        // タグ以降のコミット
        if let lastTag = sortedTags.last {
            let afterTagCommits = commits.filter { $0.date > lastTag.date }
            if !afterTagCommits.isEmpty {
                groups.append(CommitGroup(
                    id: "after-\(lastTag.name)",
                    name: "\(lastTag.name) → HEAD",
                    commits: afterTagCommits,
                    startDate: lastTag.date,
                    endDate: Date()
                ))
            }
        }

        return groups
    }
}

/// 時間ベースグルーピング
struct TimeBasedGrouping: GroupingStrategy {
    enum Interval {
        case day, week, month

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }
    }

    let interval: Interval

    func group(commits: [Commit], tags: [Tag]) -> [CommitGroup] {
        let calendar = Calendar.current
        var grouped: [String: [Commit]] = [:]

        for commit in commits {
            let components = calendar.dateComponents(
                [.year, interval.component],
                from: commit.date
            )
            let key = formatGroupKey(components)
            grouped[key, default: []].append(commit)
        }

        return grouped.map { key, commits in
            CommitGroup(
                id: key,
                name: key,
                commits: commits.sorted { $0.date < $1.date },
                startDate: commits.map(\.date).min() ?? Date(),
                endDate: commits.map(\.date).max() ?? Date()
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    private func formatGroupKey(_ components: DateComponents) -> String {
        let year = components.year ?? 0
        switch interval {
        case .day:
            return "\(year)-\(components.day ?? 0)"
        case .week:
            return "\(year)年 第\(components.weekOfYear ?? 0)週"
        case .month:
            return "\(year)年\(components.month ?? 0)月"
        }
    }
}

/// 複合戦略（推奨）
struct CompositeGrouping: GroupingStrategy {
    func group(commits: [Commit], tags: [Tag]) -> [CommitGroup] {
        // タグが3つ以上あればタグベース
        if tags.count >= 3 {
            return TagBasedGrouping().group(commits: commits, tags: tags)
        }

        // それ以外は週ベース
        return TimeBasedGrouping(interval: .week).group(commits: commits, tags: tags)
    }
}
```

---

## 6. プロンプト生成

### 6.1 PromptGenerator

```swift
/// プロンプト生成
struct PromptGenerator {
    var language: String = "Japanese"

    func commitPrompt(commit: Commit, diff: DiffStats) -> String {
        """
        You are a software development expert. Analyze this commit and explain its purpose concisely.

        ## Commit Info
        - SHA: \(commit.sha.prefix(8))
        - Author: \(commit.author)
        - Date: \(commit.date.formatted())
        - Message: \(commit.message)

        ## Changes
        - Files changed: \(diff.filesChanged.count)
        - Additions: +\(diff.additions)
        - Deletions: -\(diff.deletions)
        - Changed files: \(diff.filesChanged.prefix(10).map(\.path).joined(separator: ", "))

        ## Output (JSON, in \(language))
        {
          "summary": "1-2 sentence explanation of this commit's purpose",
          "category": "feature|fix|refactor|docs|test|chore|style|perf",
          "impact": "high|medium|low",
          "keywords": ["keyword1", "keyword2"]
        }
        """
    }

    func groupPrompt(group: CommitGroup, summaries: [CommitSummary]) -> String {
        let summaryList = summaries.map { "- [\($0.category.rawValue)] \($0.summary)" }
            .joined(separator: "\n")

        return """
        You are a technical writer. Create a narrative summary of this development period.

        ## Period
        \(group.name)
        \(group.startDate.formatted()) - \(group.endDate.formatted())

        ## Commit Summaries
        \(summaryList)

        ## Statistics
        - Total commits: \(group.commits.count)
        - Contributors: \(Set(group.commits.map(\.author)).joined(separator: ", "))

        ## Output (JSON, in \(language))
        {
          "narrative": "2-3 paragraph story about this development period",
          "highlights": ["highlight 1", "highlight 2", "highlight 3"],
          "themes": ["theme 1", "theme 2"]
        }
        """
    }

    func versionPrompt(tag: Tag, groups: [GroupSummary]) -> String {
        let narratives = groups.map(\.narrative).joined(separator: "\n\n")

        return """
        You are a release manager. Create release notes for this version.

        ## Version: \(tag.name)

        ## Period Summaries
        \(narratives)

        ## Output (JSON, in \(language))
        {
          "releaseTitle": "Catchy title for this release",
          "overview": "2-3 sentence overview",
          "newFeatures": ["feature 1", "feature 2"],
          "improvements": ["improvement 1"],
          "bugFixes": ["fix 1"],
          "breakingChanges": []
        }
        """
    }

    func projectStoryPrompt(versions: [VersionSummary]) -> String {
        let timeline = versions.map { "### \($0.version)\n\($0.overview)" }
            .joined(separator: "\n\n")

        return """
        You are a software historian. Create the evolution story of this project.

        ## Version History
        \(timeline)

        ## Output (JSON, in \(language))
        {
          "tagline": "One-line description of the project",
          "origin": "How and why the project started",
          "evolution": "How it evolved over time",
          "philosophy": "Design philosophy and principles",
          "challenges": "Major challenges overcome",
          "milestones": [
            {"version": "v1.0", "significance": "Why it matters"}
          ]
        }
        """
    }
}
```

---

## 7. エラーハンドリング

```swift
/// GitTaleエラー
enum GitTaleError: LocalizedError {
    case gitNotFound
    case notARepository(URL)
    case gitCommandFailed(String)
    case aiProviderUnavailable(String)
    case aiRateLimitExceeded
    case cacheCorrupted(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git is not installed"
        case .notARepository(let url):
            return "'\(url.lastPathComponent)' is not a Git repository"
        case .gitCommandFailed(let msg):
            return "Git command failed: \(msg)"
        case .aiProviderUnavailable(let name):
            return "\(name) is not available"
        case .aiRateLimitExceeded:
            return "API rate limit exceeded. Please wait and retry."
        case .cacheCorrupted(let path):
            return "Cache file corrupted: \(path)"
        case .parseError(let msg):
            return "Failed to parse AI response: \(msg)"
        }
    }
}
```
