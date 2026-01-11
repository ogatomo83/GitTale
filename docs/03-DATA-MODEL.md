# GitTale - データモデル設計書

## 1. 設計方針

### 1.1 DBレスアーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                       Data Flow                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   .git/                       App Memory                        │
│   ┌─────────────┐            ┌─────────────────────────────┐   │
│   │ git log     │ ────────▶  │ [Commit]                    │   │
│   │ git diff    │            │ [Tag]                       │   │
│   │ git tag     │            │ [DiffStats]                 │   │
│   └─────────────┘            └─────────────────────────────┘   │
│                                        │                        │
│                                        ▼                        │
│   .gittale/cache/            ┌─────────────────────────────┐   │
│   ┌─────────────┐            │ AI Processing               │   │
│   │ {sha}.json  │ ◀────────▶ │ (SummaryEngine)             │   │
│   │ groups/     │            └─────────────────────────────┘   │
│   │ versions/   │                      │                        │
│   │ story.json  │                      ▼                        │
│   └─────────────┘            ┌─────────────────────────────┐   │
│                              │ [CommitSummary]             │   │
│                              │ [GroupSummary]              │   │
│                              │ [VersionSummary]            │   │
│                              │ [ProjectStory]              │   │
│                              └─────────────────────────────┘   │
│                                                                 │
│   ※ SwiftData/SQLite は使用しない                               │
│   ※ Gitから取得したデータはメモリ上のみ                          │
│   ※ AI要約のみJSONファイルでキャッシュ                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 モデル分類

| 分類 | 保存先 | ライフサイクル |
|------|--------|---------------|
| **Git由来データ** | なし（毎回取得） | アプリ実行中のみ |
| **AI要約データ** | .gittale/cache/ | 永続化（JSONファイル） |
| **設定データ** | UserDefaults + Keychain | 永続化 |

---

## 2. Git由来モデル（メモリのみ）

### 2.1 Commit

```swift
/// コミット情報（Gitから取得）
struct Commit: Identifiable, Hashable {
    let sha: String
    let author: String
    let email: String
    let date: Date
    let message: String
    let parentSHAs: [String]

    var id: String { sha }

    /// 短縮SHA（表示用）
    var shortSHA: String {
        String(sha.prefix(8))
    }

    /// コミットメッセージの1行目
    var subject: String {
        message.components(separatedBy: "\n").first ?? message
    }

    /// マージコミットかどうか
    var isMergeCommit: Bool {
        parentSHAs.count > 1
    }
}
```

### 2.2 Tag

```swift
/// タグ情報（Gitから取得）
struct Tag: Identifiable, Hashable {
    let name: String
    let commitSHA: String
    let date: Date

    var id: String { name }

    /// セマンティックバージョンかどうか
    var isSemanticVersion: Bool {
        let pattern = #"^v?\d+\.\d+\.\d+"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// バージョン番号を抽出（ソート用）
    var versionComponents: (major: Int, minor: Int, patch: Int)? {
        let pattern = #"v?(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let majorRange = Range(match.range(at: 1), in: name),
              let minorRange = Range(match.range(at: 2), in: name),
              let patchRange = Range(match.range(at: 3), in: name) else {
            return nil
        }

        return (
            Int(name[majorRange]) ?? 0,
            Int(name[minorRange]) ?? 0,
            Int(name[patchRange]) ?? 0
        )
    }
}
```

### 2.3 DiffStats

```swift
/// Diff統計情報（Gitから取得）
struct DiffStats {
    let additions: Int
    let deletions: Int
    let filesChanged: [FileChange]

    var totalChanges: Int {
        additions + deletions
    }

    var fileCount: Int {
        filesChanged.count
    }

    /// 変更種別を推論
    var inferredCategory: ChangeCategory {
        let paths = filesChanged.map(\.path)

        // テストファイルのみ
        if paths.allSatisfy({ $0.contains("test") || $0.contains("spec") }) {
            return .test
        }

        // ドキュメントのみ
        if paths.allSatisfy({ $0.hasSuffix(".md") || $0.contains("docs/") }) {
            return .docs
        }

        // 設定ファイルのみ
        let configExtensions = [".json", ".yml", ".yaml", ".toml", ".xml"]
        if paths.allSatisfy({ path in configExtensions.contains(where: { path.hasSuffix($0) }) }) {
            return .chore
        }

        // 追加≈削除 → リファクタリング
        if additions > 0 && deletions > 0 {
            let ratio = Double(min(additions, deletions)) / Double(max(additions, deletions))
            if ratio > 0.7 {
                return .refactor
            }
        }

        // 追加のみ → 機能追加
        if additions > 0 && deletions == 0 {
            return .feature
        }

        return .change
    }
}

/// ファイル変更情報
struct FileChange: Hashable {
    let path: String
    let status: Status

    enum Status: String {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
    }

    /// ファイル拡張子
    var fileExtension: String {
        (path as NSString).pathExtension
    }

    /// ディレクトリパス
    var directory: String {
        (path as NSString).deletingLastPathComponent
    }
}
```

### 2.4 CommitGroup

```swift
/// コミットグループ（メモリ上で生成）
struct CommitGroup: Identifiable {
    let id: String
    let name: String
    let commits: [Commit]
    let startDate: Date
    let endDate: Date
    var tag: Tag?

    var commitCount: Int {
        commits.count
    }

    var authors: [String] {
        Array(Set(commits.map(\.author)))
    }

    var authorCount: Int {
        authors.count
    }
}
```

---

## 3. AI要約モデル（JSONキャッシュ）

### 3.1 CommitSummary

```swift
/// コミット要約（AI生成、キャッシュ対象）
struct CommitSummary: Codable, Identifiable {
    let sha: String
    let summary: String
    let category: ChangeCategory
    let impact: Impact
    let keywords: [String]
    let generatedAt: Date
    let providerName: String

    var id: String { sha }
}

/// 変更カテゴリ
enum ChangeCategory: String, Codable, CaseIterable {
    case feature = "feature"
    case fix = "fix"
    case refactor = "refactor"
    case docs = "docs"
    case test = "test"
    case chore = "chore"
    case style = "style"
    case perf = "perf"
    case change = "change"  // デフォルト

    var displayName: String {
        switch self {
        case .feature: return "Feature"
        case .fix: return "Bug Fix"
        case .refactor: return "Refactor"
        case .docs: return "Docs"
        case .test: return "Test"
        case .chore: return "Chore"
        case .style: return "Style"
        case .perf: return "Performance"
        case .change: return "Change"
        }
    }

    var icon: String {
        switch self {
        case .feature: return "plus.circle.fill"
        case .fix: return "ladybug.fill"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .docs: return "doc.text.fill"
        case .test: return "checkmark.seal.fill"
        case .chore: return "wrench.fill"
        case .style: return "paintbrush.fill"
        case .perf: return "bolt.fill"
        case .change: return "square.and.pencil"
        }
    }

    var color: String {
        switch self {
        case .feature: return "green"
        case .fix: return "red"
        case .refactor: return "purple"
        case .docs: return "blue"
        case .test: return "yellow"
        case .chore: return "gray"
        case .style: return "pink"
        case .perf: return "orange"
        case .change: return "gray"
        }
    }
}

/// 重要度
enum Impact: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        rawValue.capitalized
    }
}
```

### 3.2 GroupSummary

```swift
/// グループ要約（AI生成、キャッシュ対象）
struct GroupSummary: Codable, Identifiable {
    let groupId: String
    let narrative: String
    let highlights: [String]
    let themes: [String]
    let generatedAt: Date
    let providerName: String

    var id: String { groupId }
}
```

### 3.3 VersionSummary

```swift
/// バージョン要約（AI生成、キャッシュ対象）
struct VersionSummary: Codable, Identifiable {
    let version: String
    let releaseTitle: String
    let overview: String
    let newFeatures: [String]
    let improvements: [String]
    let bugFixes: [String]
    let breakingChanges: [String]
    let generatedAt: Date
    let providerName: String

    var id: String { version }

    var hasBreakingChanges: Bool {
        !breakingChanges.isEmpty
    }
}
```

### 3.4 ProjectStory

```swift
/// プロジェクトストーリー（AI生成、キャッシュ対象）
struct ProjectStory: Codable {
    let tagline: String
    let origin: String
    let evolution: String
    let philosophy: String
    let challenges: String
    let milestones: [Milestone]
    let generatedAt: Date
    let providerName: String
}

struct Milestone: Codable {
    let version: String
    let significance: String
}
```

---

## 4. JSONキャッシュ形式

### 4.1 ディレクトリ構造

```
.gittale/
├── .gitignore              # "**" で全体を無視
└── cache/
    ├── commits/
    │   ├── abc1234def5678....json
    │   └── 123abcd456efgh....json
    ├── groups/
    │   ├── v1.0.0-v1.1.0.json
    │   └── 2024-w03.json
    ├── versions/
    │   ├── v1.0.0.json
    │   └── v1.1.0.json
    └── story.json
```

### 4.2 キャッシュファイル例

**commits/abc1234....json:**
```json
{
  "sha": "abc1234def5678901234567890abcdef12345678",
  "summary": "ユーザー認証機能を追加し、JWTベースのセッション管理を実装",
  "category": "feature",
  "impact": "high",
  "keywords": ["authentication", "JWT", "security"],
  "generatedAt": "2024-01-15T10:30:00Z",
  "providerName": "OpenAI"
}
```

**groups/v1.0.0-v1.1.0.json:**
```json
{
  "groupId": "v1.0.0-v1.1.0",
  "narrative": "このリリースサイクルでは、主にユーザー体験の向上に焦点が当てられました...",
  "highlights": [
    "ダークモード対応",
    "パフォーマンス30%改善",
    "新しい検索機能"
  ],
  "themes": ["UX改善", "パフォーマンス"],
  "generatedAt": "2024-01-15T11:00:00Z",
  "providerName": "OpenAI"
}
```

**versions/v1.1.0.json:**
```json
{
  "version": "v1.1.0",
  "releaseTitle": "The Performance Release",
  "overview": "v1.1.0では、アプリケーション全体のパフォーマンスを大幅に改善しました...",
  "newFeatures": ["ダークモード", "オフラインモード"],
  "improvements": ["起動時間50%短縮", "メモリ使用量削減"],
  "bugFixes": ["ログイン時のクラッシュ修正"],
  "breakingChanges": [],
  "generatedAt": "2024-01-15T11:30:00Z",
  "providerName": "OpenAI"
}
```

**story.json:**
```json
{
  "tagline": "シンプルで高速なタスク管理ツール",
  "origin": "2020年、個人のタスク管理ニーズから始まったこのプロジェクトは...",
  "evolution": "初期のシンプルなCLIツールから、フル機能のGUIアプリへと進化...",
  "philosophy": "シンプルさと速度を最優先に設計。機能追加よりも既存機能の磨き込みを重視...",
  "challenges": "v1.5でのアーキテクチャ刷新は大きな挑戦でした...",
  "milestones": [
    {"version": "v1.0.0", "significance": "初の安定版リリース"},
    {"version": "v2.0.0", "significance": "GUIアプリへの転換"}
  ],
  "generatedAt": "2024-01-15T12:00:00Z",
  "providerName": "OpenAI"
}
```

---

## 5. 設定データ

### 5.1 AppSettings（UserDefaults）

```swift
/// アプリ設定
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - AI Provider

    var selectedProvider: AIProviderType {
        get {
            AIProviderType(rawValue: UserDefaults.standard.string(forKey: "selectedProvider") ?? "") ?? .openai
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedProvider")
        }
    }

    var openAIModel: String {
        get { UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4-turbo-preview" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIModel") }
    }

    var ollamaHost: String {
        get { UserDefaults.standard.string(forKey: "ollamaHost") ?? "localhost" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaHost") }
    }

    var ollamaPort: Int {
        get { UserDefaults.standard.integer(forKey: "ollamaPort").nonZero ?? 11434 }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaPort") }
    }

    var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    // MARK: - Output

    var outputLanguage: OutputLanguage {
        get {
            OutputLanguage(rawValue: UserDefaults.standard.string(forKey: "outputLanguage") ?? "") ?? .japanese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "outputLanguage")
        }
    }

    // MARK: - Recent Repositories

    var recentRepositories: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentRepositories") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentRepositories") }
    }

    func addRecentRepository(_ path: String) {
        var recent = recentRepositories.filter { $0 != path }
        recent.insert(path, at: 0)
        recentRepositories = Array(recent.prefix(10))  // 最大10件
    }

    private init() {}
}

enum AIProviderType: String, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .ollama: return "Ollama (Local)"
        }
    }

    var isLocal: Bool {
        self == .ollama
    }
}

enum OutputLanguage: String, CaseIterable {
    case japanese = "Japanese"
    case english = "English"

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
```

### 5.2 APIキー（Keychain）

```swift
import Security

/// Keychain管理
enum KeychainManager {
    private static let service = "com.gittale.apikeys"

    static func save(apiKey: String, for provider: AIProviderType) throws {
        let account = provider.rawValue
        let data = apiKey.data(using: .utf8)!

        // 既存を削除
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 新規保存
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    static func get(for provider: AIProviderType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    static func delete(for provider: AIProviderType) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed
}
```

---

## 6. ViewModel用の複合型

```swift
/// タイムライン表示用（Git情報 + AI要約を結合）
struct TimelineEntry: Identifiable {
    let commit: Commit
    let diff: DiffStats
    var summary: CommitSummary?

    var id: String { commit.sha }

    var displayCategory: ChangeCategory {
        summary?.category ?? diff.inferredCategory
    }
}

/// グループ表示用
struct GroupEntry: Identifiable {
    let group: CommitGroup
    let entries: [TimelineEntry]
    var summary: GroupSummary?

    var id: String { group.id }
}

/// バージョン表示用
struct VersionEntry: Identifiable {
    let tag: Tag
    let groups: [GroupEntry]
    var summary: VersionSummary?

    var id: String { tag.name }
}
```
