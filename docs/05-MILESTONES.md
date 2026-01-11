# GitTale - 開発マイルストーン（詳細版）

## 概要

```
Phase 1: Core       →  Git読み取り + 基本UI + OpenAI要約
Phase 2: Polish     →  階層的要約 + キャッシュ + 複数プロバイダー
Phase 3: Release    →  ローカルLLM + パフォーマンス + App Store
```

---

# Phase 1: Core（基盤）

## 1.1 プロジェクト初期設定

### 1.1.1 Xcodeプロジェクト作成
- [ ] File > New > Project > macOS > App
- [ ] Product Name: GitTale
- [ ] Interface: SwiftUI
- [ ] Language: Swift
- [ ] Bundle Identifier: com.yourname.gittale
- [ ] Deployment Target: macOS 14.0

### 1.1.2 ディレクトリ構造作成
- [ ] `App/` フォルダ作成
- [ ] `Models/` フォルダ作成
- [ ] `Models/Summaries/` サブフォルダ作成
- [ ] `Views/` フォルダ作成
- [ ] `Views/Sidebar/` サブフォルダ作成
- [ ] `Views/Timeline/` サブフォルダ作成
- [ ] `Views/Detail/` サブフォルダ作成
- [ ] `Views/Settings/` サブフォルダ作成
- [ ] `Views/Components/` サブフォルダ作成
- [ ] `ViewModels/` フォルダ作成
- [ ] `Services/` フォルダ作成
- [ ] `Services/Git/` サブフォルダ作成
- [ ] `Services/AI/` サブフォルダ作成
- [ ] `Services/Cache/` サブフォルダ作成
- [ ] `Utilities/` フォルダ作成

### 1.1.3 基本ファイル作成
- [ ] `App/GitTaleApp.swift` - エントリーポイント
- [ ] `Views/ContentView.swift` - ルートビュー
- [ ] `Utilities/Constants.swift` - 定数定義

---

## 1.2 データモデル定義

### 1.2.1 Commit モデル
- [ ] `Models/Commit.swift` ファイル作成
- [ ] `struct Commit` 定義
- [ ] プロパティ: `sha: String`
- [ ] プロパティ: `author: String`
- [ ] プロパティ: `email: String`
- [ ] プロパティ: `date: Date`
- [ ] プロパティ: `message: String`
- [ ] プロパティ: `parentSHAs: [String]`
- [ ] `Identifiable` 準拠 (`id` = `sha`)
- [ ] `Hashable` 準拠
- [ ] computed: `shortSHA` (8文字)
- [ ] computed: `subject` (1行目)
- [ ] computed: `isMergeCommit` (親が2つ以上)

### 1.2.2 Tag モデル
- [ ] `Models/Tag.swift` ファイル作成
- [ ] `struct Tag` 定義
- [ ] プロパティ: `name: String`
- [ ] プロパティ: `commitSHA: String`
- [ ] プロパティ: `date: Date`
- [ ] `Identifiable` 準拠
- [ ] `Hashable` 準拠
- [ ] computed: `isSemanticVersion` (正規表現判定)
- [ ] computed: `versionComponents` (major, minor, patch)

### 1.2.3 DiffStats モデル
- [ ] `Models/DiffStats.swift` ファイル作成
- [ ] `struct DiffStats` 定義
- [ ] プロパティ: `additions: Int`
- [ ] プロパティ: `deletions: Int`
- [ ] プロパティ: `filesChanged: [FileChange]`
- [ ] computed: `totalChanges`
- [ ] computed: `fileCount`
- [ ] computed: `inferredCategory`

### 1.2.4 FileChange モデル
- [ ] `struct FileChange` 定義 (DiffStats.swift内)
- [ ] プロパティ: `path: String`
- [ ] プロパティ: `status: Status`
- [ ] `enum Status`: added, modified, deleted, renamed
- [ ] `Hashable` 準拠
- [ ] computed: `fileExtension`
- [ ] computed: `directory`

### 1.2.5 ChangeCategory 列挙型
- [ ] `Models/ChangeCategory.swift` ファイル作成
- [ ] `enum ChangeCategory: String, Codable`
- [ ] case: feature, fix, refactor, docs, test, chore, style, perf, change
- [ ] computed: `displayName`
- [ ] computed: `icon` (SF Symbol名)
- [ ] computed: `color`

### 1.2.6 Impact 列挙型
- [ ] `enum Impact: String, Codable` (ChangeCategory.swift内)
- [ ] case: high, medium, low
- [ ] computed: `displayName`

### 1.2.7 CommitGroup モデル
- [ ] `Models/CommitGroup.swift` ファイル作成
- [ ] `struct CommitGroup` 定義
- [ ] プロパティ: `id: String`
- [ ] プロパティ: `name: String`
- [ ] プロパティ: `commits: [Commit]`
- [ ] プロパティ: `startDate: Date`
- [ ] プロパティ: `endDate: Date`
- [ ] プロパティ: `tag: Tag?`
- [ ] `Identifiable` 準拠
- [ ] computed: `commitCount`
- [ ] computed: `authors`

---

## 1.3 Git統合

### 1.3.1 GitError 定義
- [ ] `Services/Git/GitError.swift` ファイル作成
- [ ] `enum GitError: LocalizedError`
- [ ] case: `notARepository`
- [ ] case: `commandFailed(String, String)`
- [ ] case: `parseError(String)`
- [ ] `errorDescription` 実装

### 1.3.2 GitCLI ラッパー
- [ ] `Services/Git/GitCLI.swift` ファイル作成
- [ ] `actor GitCLI` 定義
- [ ] プロパティ: `repositoryPath: URL`
- [ ] `init(repositoryPath:)`
- [ ] `func execute(_ arguments: [String]) async throws -> String`
- [ ] Process生成
- [ ] stdout/stderr Pipe設定
- [ ] 非同期実行
- [ ] 終了ステータスチェック
- [ ] エラーハンドリング

### 1.3.3 GitRepository - 初期化
- [ ] `Services/Git/GitRepository.swift` ファイル作成
- [ ] `actor GitRepository` 定義
- [ ] プロパティ: `path: URL`
- [ ] プロパティ: `git: GitCLI`
- [ ] `init(path:) throws`
- [ ] .git ディレクトリ存在確認

### 1.3.4 GitRepository - コミット取得
- [ ] `func getAllCommits() async throws -> [Commit]`
- [ ] git log フォーマット文字列定義: `%H|%an|%ae|%aI|%s|%P`
- [ ] `--reverse --all` オプション
- [ ] 出力パース
- [ ] `private func parseCommit(_ line: String) -> Commit?`
- [ ] 日付パース (ISO8601)
- [ ] 親SHA分割

### 1.3.5 GitRepository - 最初のコミット
- [ ] `func getFirstCommit() async throws -> Commit?`
- [ ] `git log --reverse -1` 実行

### 1.3.6 GitRepository - 差分コミット
- [ ] `func getCommits(since sha: String) async throws -> [Commit]`
- [ ] `{sha}..HEAD` 範囲指定

### 1.3.7 GitRepository - Diff統計
- [ ] `func getDiffStats(for sha: String) async throws -> DiffStats`
- [ ] `git diff --stat` 実行
- [ ] `git diff --name-status` 実行
- [ ] `private func parseDiffStats(stat:nameStatus:) -> DiffStats`
- [ ] 追加/削除行数抽出
- [ ] ファイル変更状態パース

### 1.3.8 GitRepository - タグ取得
- [ ] `func getAllTags() async throws -> [Tag]`
- [ ] `git tag -l --format=...` 実行
- [ ] フォーマット: `%(refname:short)|%(objectname:short)|%(creatordate:iso-strict)`
- [ ] `private func parseTag(_ line: String) -> Tag?`
- [ ] annotated/lightweight タグ判別

### 1.3.9 GitRepository - ブランチ
- [ ] `func getCurrentBranch() async throws -> String`
- [ ] `git branch --show-current` 実行

### 1.3.10 GitRepository - テスト
- [ ] 実際のリポジトリでコミット取得テスト
- [ ] タグ取得テスト
- [ ] Diff統計テスト

---

## 1.4 基本UI - ウェルカム画面

### 1.4.1 WelcomeView 基本構造
- [ ] `Views/WelcomeView.swift` ファイル作成
- [ ] `struct WelcomeView: View`
- [ ] VStack レイアウト
- [ ] アイコン表示 (SF Symbol: book.pages)
- [ ] "Drop a Git Repository" テキスト
- [ ] "or" テキスト
- [ ] "Browse..." ボタン

### 1.4.2 WelcomeView ドラッグ&ドロップ
- [ ] `@State private var isDragging: Bool`
- [ ] `.onDrop(of: [.fileURL], isTargeted:)` 修飾子
- [ ] `handleDrop(_ providers:) -> Bool` 実装
- [ ] NSItemProvider からURL抽出
- [ ] ドラッグ中の背景色変更

### 1.4.3 WelcomeView ファイルピッカー
- [ ] `@State private var showFilePicker: Bool`
- [ ] `.fileImporter()` 修飾子
- [ ] ディレクトリ選択許可
- [ ] 選択後のコールバック

---

## 1.5 基本UI - サイドバー

### 1.5.1 SidebarView 基本構造
- [ ] `Views/Sidebar/SidebarView.swift` ファイル作成
- [ ] `struct SidebarView: View`
- [ ] `@Binding var selectedView: SidebarItem`
- [ ] List with selection
- [ ] `.listStyle(.sidebar)` 適用

### 1.5.2 SidebarItem 定義
- [ ] `enum SidebarItem: Hashable`
- [ ] case: timeline, story, settings

### 1.5.3 SidebarView セクション
- [ ] リポジトリヘッダーセクション
- [ ] メインナビゲーションセクション (Timeline, Story)
- [ ] Recentセクション
- [ ] Settingsセクション

### 1.5.4 RepositoryHeader コンポーネント
- [ ] `Views/Sidebar/RepositoryHeader.swift` ファイル作成
- [ ] フォルダアイコン + リポジトリ名表示

### 1.5.5 RecentRepositoryRow コンポーネント
- [ ] `Views/Sidebar/RecentRepositoryRow.swift` ファイル作成
- [ ] パス表示
- [ ] タップでリポジトリ開く

---

## 1.6 基本UI - タイムライン

### 1.6.1 TimelineView 基本構造
- [ ] `Views/Timeline/TimelineView.swift` ファイル作成
- [ ] `struct TimelineView: View`
- [ ] VStack: ツールバー + コンテンツ
- [ ] ScrollView + LazyVStack

### 1.6.2 TimelineView ローディング状態
- [ ] ローディング中: ProgressView表示
- [ ] ロード完了: コミット一覧表示

### 1.6.3 CommitRow コンポーネント
- [ ] `Views/Timeline/CommitRow.swift` ファイル作成
- [ ] HStack レイアウト
- [ ] カテゴリアイコン
- [ ] コミットメッセージ (subject)
- [ ] メタデータ行 (SHA, Author, Date)
- [ ] 選択状態のハイライト

### 1.6.4 CategoryIcon コンポーネント
- [ ] `Views/Components/CategoryIcon.swift` ファイル作成
- [ ] SF Symbol表示
- [ ] カテゴリに応じた色

### 1.6.5 TimelineToolbar
- [ ] `Views/Timeline/TimelineToolbar.swift` ファイル作成
- [ ] リフレッシュボタン
- [ ] (Phase 2でズームレベル追加)

---

## 1.7 基本UI - 詳細ビュー

### 1.7.1 DetailView 基本構造
- [ ] `Views/Detail/DetailView.swift` ファイル作成
- [ ] 選択なし: EmptyDetailView表示
- [ ] 選択あり: CommitDetailView表示

### 1.7.2 EmptyDetailView
- [ ] `Views/Detail/EmptyDetailView.swift` ファイル作成
- [ ] ContentUnavailableView使用
- [ ] "Select a Commit" メッセージ

### 1.7.3 CommitDetailView 基本
- [ ] `Views/Detail/CommitDetailView.swift` ファイル作成
- [ ] ScrollView
- [ ] ヘッダー (subject + カテゴリバッジ)

### 1.7.4 CommitDetailView メタデータ
- [ ] SHA表示 (コピー可能)
- [ ] Author + Email表示
- [ ] Date表示
- [ ] Parent SHA表示

### 1.7.5 CommitDetailView Diff統計
- [ ] 追加/削除行数表示
- [ ] ファイル数表示
- [ ] ファイル一覧 (FileChangeRow)

### 1.7.6 FileChangeRow
- [ ] `Views/Detail/FileChangeRow.swift` ファイル作成
- [ ] ステータスアイコン (A/M/D/R)
- [ ] ファイルパス表示

---

## 1.8 基本UI - メイン統合

### 1.8.1 ContentView 実装
- [ ] NavigationSplitView 3カラム
- [ ] sidebar: SidebarView
- [ ] content: 条件分岐 (WelcomeView / TimelineView)
- [ ] detail: DetailView

### 1.8.2 AppViewModel 基本
- [ ] `ViewModels/AppViewModel.swift` ファイル作成
- [ ] `@Observable class AppViewModel`
- [ ] プロパティ: `currentRepository: GitRepository?`
- [ ] プロパティ: `commits: [Commit]`
- [ ] プロパティ: `isLoading: Bool`
- [ ] プロパティ: `error: Error?`

### 1.8.3 AppViewModel - リポジトリ操作
- [ ] `func openRepository(at url: URL)`
- [ ] GitRepository初期化
- [ ] コミット取得
- [ ] エラーハンドリング

### 1.8.4 AppViewModel - 状態管理
- [ ] `@Published` 適切に設定
- [ ] MainActorでUI更新

---

## 1.9 設定 - 基本

### 1.9.1 AppSettings
- [ ] `Utilities/AppSettings.swift` ファイル作成
- [ ] `@Observable class AppSettings`
- [ ] `static let shared` シングルトン
- [ ] UserDefaults連携

### 1.9.2 AppSettings - プロバイダー設定
- [ ] `selectedProvider: AIProviderType` プロパティ
- [ ] `openAIModel: String` プロパティ

### 1.9.3 AppSettings - 出力設定
- [ ] `outputLanguage: OutputLanguage` プロパティ

### 1.9.4 AppSettings - 履歴
- [ ] `recentRepositories: [String]` プロパティ
- [ ] `func addRecentRepository(_ path: String)`
- [ ] 最大10件制限

### 1.9.5 AIProviderType 列挙型
- [ ] `enum AIProviderType: String, CaseIterable`
- [ ] case: openai, anthropic, ollama
- [ ] `displayName` computed
- [ ] `isLocal` computed

### 1.9.6 OutputLanguage 列挙型
- [ ] `enum OutputLanguage: String, CaseIterable`
- [ ] case: japanese, english
- [ ] `displayName` computed

---

## 1.10 設定 - Keychain

### 1.10.1 KeychainManager
- [ ] `Utilities/KeychainManager.swift` ファイル作成
- [ ] `enum KeychainManager`
- [ ] `private static let service = "com.gittale.apikeys"`

### 1.10.2 KeychainManager - 保存
- [ ] `static func save(apiKey:for:) throws`
- [ ] 既存キー削除
- [ ] SecItemAdd呼び出し
- [ ] ステータスチェック

### 1.10.3 KeychainManager - 取得
- [ ] `static func get(for:) -> String?`
- [ ] SecItemCopyMatching呼び出し
- [ ] Data→String変換

### 1.10.4 KeychainManager - 削除
- [ ] `static func delete(for:)`
- [ ] SecItemDelete呼び出し

### 1.10.5 KeychainError
- [ ] `enum KeychainError: Error`
- [ ] case: saveFailed

---

## 1.11 設定UI

### 1.11.1 SettingsView 基本
- [ ] `Views/Settings/SettingsView.swift` ファイル作成
- [ ] Form + .formStyle(.grouped)
- [ ] AI Providerセクション
- [ ] Outputセクション

### 1.11.2 SettingsView - プロバイダー選択
- [ ] Picker for AIProviderType
- [ ] プロバイダー別設定表示切替

### 1.11.3 OpenAISettings
- [ ] `Views/Settings/OpenAISettings.swift` ファイル作成
- [ ] APIキー表示 (マスク済み)
- [ ] "Change" ボタン
- [ ] モデル選択Picker

### 1.11.4 APIKeyInputSheet
- [ ] `Views/Settings/APIKeyInputSheet.swift` ファイル作成
- [ ] SecureField
- [ ] Save/Cancelボタン
- [ ] Keychain保存

### 1.11.5 ConnectionStatusView
- [ ] `Views/Components/ConnectionStatusView.swift` ファイル作成
- [ ] ステータス別表示 (unknown, checking, connected, disconnected)
- [ ] インジケーターアイコン

---

## 1.12 AI統合 - 基本

### 1.12.1 AIProvider プロトコル
- [ ] `Services/AI/AIProvider.swift` ファイル作成
- [ ] `protocol AIProvider: Sendable`
- [ ] `var name: String { get }`
- [ ] `func complete(prompt: String) async throws -> String`
- [ ] `func isAvailable() async -> Bool`

### 1.12.2 AIError 定義
- [ ] `Services/AI/AIError.swift` ファイル作成
- [ ] `enum AIError: LocalizedError`
- [ ] case: providerUnavailable, rateLimitExceeded, invalidResponse, networkError

### 1.12.3 OpenAIProvider - 基本
- [ ] `Services/AI/OpenAIProvider.swift` ファイル作成
- [ ] `final class OpenAIProvider: AIProvider`
- [ ] プロパティ: apiKey, model
- [ ] `init(apiKey:model:)`

### 1.12.4 OpenAIProvider - complete
- [ ] URL構築: `https://api.openai.com/v1/chat/completions`
- [ ] URLRequest作成
- [ ] Authorization ヘッダー設定
- [ ] Content-Type ヘッダー設定
- [ ] リクエストボディ構築 (JSON)
- [ ] URLSession.shared.data(for:) 呼び出し
- [ ] レスポンスパース
- [ ] エラーハンドリング

### 1.12.5 OpenAIProvider - isAvailable
- [ ] APIキー存在チェック

### 1.12.6 OpenAI レスポンス型
- [ ] `struct OpenAIResponse: Decodable`
- [ ] choices配列
- [ ] message.content取得

---

## 1.13 AI統合 - プロンプト

### 1.13.1 PromptGenerator 基本
- [ ] `Services/AI/PromptGenerator.swift` ファイル作成
- [ ] `struct PromptGenerator`
- [ ] プロパティ: `language: String`

### 1.13.2 PromptGenerator - コミット要約
- [ ] `func commitPrompt(commit:diff:) -> String`
- [ ] コミット情報セクション
- [ ] 変更統計セクション
- [ ] 出力形式指定 (JSON)
- [ ] 言語指定

### 1.13.3 CommitSummary モデル
- [ ] `Models/Summaries/CommitSummary.swift` ファイル作成
- [ ] `struct CommitSummary: Codable, Identifiable`
- [ ] プロパティ: sha, summary, category, impact, keywords
- [ ] プロパティ: generatedAt, providerName

### 1.13.4 CommitSummaryResponse (パース用)
- [ ] AI応答パース用の内部構造体
- [ ] JSONDecoder使用

---

## 1.14 AI統合 - SummaryEngine

### 1.14.1 SummaryEngine 基本
- [ ] `Services/AI/SummaryEngine.swift` ファイル作成
- [ ] `actor SummaryEngine`
- [ ] プロパティ: aiProvider, promptGenerator

### 1.14.2 SummaryEngine - 単一コミット要約
- [ ] `func summarizeCommit(_ commit:diff:) async throws -> CommitSummary`
- [ ] プロンプト生成
- [ ] AI呼び出し
- [ ] レスポンスパース
- [ ] CommitSummary生成

### 1.14.3 パースエラーハンドリング
- [ ] JSONデコード失敗時のフォールバック
- [ ] 部分的なレスポンス処理

---

## 1.15 統合テスト

### 1.15.1 E2Eテスト
- [ ] 実際のリポジトリをドロップ
- [ ] コミット一覧表示確認
- [ ] コミット選択→詳細表示確認
- [ ] OpenAI APIキー設定
- [ ] 要約生成確認

---

# Phase 2: Polish（機能充実）

## 2.1 ファイルキャッシュ

### 2.1.1 FileCache - 基本構造
- [ ] `Services/Cache/FileCache.swift` ファイル作成
- [ ] `actor FileCache`
- [ ] プロパティ: `baseDir: URL`
- [ ] `init(repositoryPath:)` - .gittale/cache/パス設定

### 2.1.2 FileCache - CacheType
- [ ] `enum CacheType: String`
- [ ] case: commit, group, version, story
- [ ] rawValueでディレクトリ名

### 2.1.3 FileCache - setup
- [ ] `func setup() throws`
- [ ] .gittaleディレクトリ作成
- [ ] cache/サブディレクトリ作成
- [ ] commits/, groups/, versions/ 作成

### 2.1.4 FileCache - .gitignore
- [ ] .gitignoreファイル作成チェック
- [ ] 内容: `# GitTale cache\n**\n`
- [ ] 書き込み

### 2.1.5 FileCache - save
- [ ] `func save<T: Encodable>(_ value:type:id:) async throws`
- [ ] パス計算
- [ ] JSONEncoder (prettyPrinted, sortedKeys)
- [ ] Data書き込み

### 2.1.6 FileCache - load
- [ ] `func load<T: Decodable>(type:id:) async throws -> T`
- [ ] パス計算
- [ ] Data読み込み
- [ ] JSONDecoder

### 2.1.7 FileCache - exists
- [ ] `func exists(type:id:) -> Bool`
- [ ] FileManager.fileExists

### 2.1.8 FileCache - delete
- [ ] `func delete(type:id:) throws`
- [ ] FileManager.removeItem

### 2.1.9 FileCache - deleteAll
- [ ] `func deleteAll(type:) throws`
- [ ] ディレクトリ削除→再作成

### 2.1.10 FileCache - invalidateGroupCaches
- [ ] `func invalidateGroupCaches() throws`
- [ ] groups, versions削除
- [ ] story.json削除

### 2.1.11 キャッシュパス計算
- [ ] `private func cachePath(type:id:) -> URL`
- [ ] story: baseDir/story.json
- [ ] その他: baseDir/{type}/{id}.json

---

## 2.2 SummaryEngine キャッシュ統合

### 2.2.1 SummaryEngine キャッシュ追加
- [ ] プロパティ追加: `cache: FileCache`
- [ ] init更新

### 2.2.2 summarizeCommit キャッシュ対応
- [ ] キャッシュ存在チェック
- [ ] ヒット時: キャッシュから返却
- [ ] ミス時: AI呼び出し→キャッシュ保存

### 2.2.3 キャッシュ初期化
- [ ] AppViewModel/起動時にcache.setup()呼び出し

---

## 2.3 グルーピング戦略

### 2.3.1 GroupingStrategy プロトコル
- [ ] `Services/Grouping/GroupingStrategy.swift` ファイル作成
- [ ] `protocol GroupingStrategy`
- [ ] `func group(commits:tags:) -> [CommitGroup]`

### 2.3.2 TagBasedGrouping
- [ ] `Services/Grouping/TagBasedGrouping.swift` ファイル作成
- [ ] `struct TagBasedGrouping: GroupingStrategy`
- [ ] タグでソート
- [ ] タグ間のコミットをグループ化
- [ ] 最初のタグ以前のコミット処理
- [ ] 最後のタグ以降のコミット処理

### 2.3.3 TimeBasedGrouping
- [ ] `Services/Grouping/TimeBasedGrouping.swift` ファイル作成
- [ ] `struct TimeBasedGrouping: GroupingStrategy`
- [ ] `enum Interval`: day, week, month
- [ ] Calendar.dateComponentsでグループ化
- [ ] グループ名フォーマット

### 2.3.4 CompositeGrouping
- [ ] `Services/Grouping/CompositeGrouping.swift` ファイル作成
- [ ] `struct CompositeGrouping: GroupingStrategy`
- [ ] タグ3つ以上: TagBasedGrouping
- [ ] それ以外: TimeBasedGrouping(week)

---

## 2.4 階層的要約モデル

### 2.4.1 GroupSummary モデル
- [ ] `Models/Summaries/GroupSummary.swift` ファイル作成
- [ ] `struct GroupSummary: Codable, Identifiable`
- [ ] プロパティ: groupId, narrative, highlights, themes
- [ ] プロパティ: generatedAt, providerName

### 2.4.2 VersionSummary モデル
- [ ] `Models/Summaries/VersionSummary.swift` ファイル作成
- [ ] `struct VersionSummary: Codable, Identifiable`
- [ ] プロパティ: version, releaseTitle, overview
- [ ] プロパティ: newFeatures, improvements, bugFixes, breakingChanges
- [ ] プロパティ: generatedAt, providerName

### 2.4.3 ProjectStory モデル
- [ ] `Models/Summaries/ProjectStory.swift` ファイル作成
- [ ] `struct ProjectStory: Codable`
- [ ] プロパティ: tagline, origin, evolution, philosophy, challenges
- [ ] プロパティ: milestones, generatedAt, providerName

### 2.4.4 Milestone モデル
- [ ] `struct Milestone: Codable`
- [ ] プロパティ: version, significance

---

## 2.5 階層的要約プロンプト

### 2.5.1 PromptGenerator - グループ要約
- [ ] `func groupPrompt(group:summaries:) -> String`
- [ ] 期間情報
- [ ] コミット要約一覧
- [ ] 統計情報
- [ ] JSON出力形式

### 2.5.2 PromptGenerator - バージョン要約
- [ ] `func versionPrompt(tag:groups:) -> String`
- [ ] バージョン情報
- [ ] グループナラティブ一覧
- [ ] リリースノート形式出力

### 2.5.3 PromptGenerator - プロジェクトストーリー
- [ ] `func projectStoryPrompt(versions:) -> String`
- [ ] バージョン履歴
- [ ] 物語形式出力

---

## 2.6 SummaryEngine 階層的要約

### 2.6.1 バッチコミット要約
- [ ] `func summarizeCommits(_:progress:) async throws -> [String: CommitSummary]`
- [ ] バッチサイズ設定 (5件ずつ)
- [ ] TaskGroup使用
- [ ] 進捗コールバック

### 2.6.2 グループ要約
- [ ] `func summarizeGroup(_:commitSummaries:) async throws -> GroupSummary`
- [ ] キャッシュチェック
- [ ] プロンプト生成
- [ ] AI呼び出し
- [ ] キャッシュ保存

### 2.6.3 バージョン要約
- [ ] `func summarizeVersion(tag:groups:) async throws -> VersionSummary`
- [ ] キャッシュチェック
- [ ] プロンプト生成
- [ ] AI呼び出し
- [ ] キャッシュ保存

### 2.6.4 プロジェクトストーリー
- [ ] `func generateProjectStory(versions:) async throws -> ProjectStory`
- [ ] キャッシュチェック
- [ ] プロンプト生成
- [ ] AI呼び出し
- [ ] キャッシュ保存

---

## 2.7 表示用複合型

### 2.7.1 TimelineEntry
- [ ] `Models/TimelineEntry.swift` ファイル作成
- [ ] `struct TimelineEntry: Identifiable`
- [ ] プロパティ: commit, diff, summary?
- [ ] computed: displayCategory

### 2.7.2 GroupEntry
- [ ] `Models/GroupEntry.swift` ファイル作成
- [ ] `struct GroupEntry: Identifiable`
- [ ] プロパティ: group, entries, summary?

### 2.7.3 VersionEntry
- [ ] `Models/VersionEntry.swift` ファイル作成
- [ ] `struct VersionEntry: Identifiable`
- [ ] プロパティ: tag, groups, summary?

---

## 2.8 UI - ズームレベル

### 2.8.1 ZoomLevel 列挙型
- [ ] `enum ZoomLevel: String, CaseIterable`
- [ ] case: day, week, month, version
- [ ] displayName computed

### 2.8.2 TimelineToolbar ズーム追加
- [ ] Picker for ZoomLevel
- [ ] .segmented スタイル

### 2.8.3 TimelineView ズーム対応
- [ ] `@State private var zoomLevel: ZoomLevel`
- [ ] zoomLevelに応じたグルーピング

### 2.8.4 AppViewModel グルーピング
- [ ] `func groupedEntries(for zoomLevel:) -> [GroupEntry]`
- [ ] グルーピング戦略適用
- [ ] TimelineEntry生成

---

## 2.9 UI - グループセクション

### 2.9.1 GroupSection 基本
- [ ] `Views/Timeline/GroupSection.swift` ファイル作成
- [ ] 展開/折りたたみ状態
- [ ] ヘッダー + コンテンツ

### 2.9.2 GroupHeader
- [ ] `Views/Timeline/GroupHeader.swift` ファイル作成
- [ ] 展開アイコン (chevron)
- [ ] タグアイコン (あれば)
- [ ] グループ名
- [ ] コミット数

### 2.9.3 GroupNarrativeCard
- [ ] `Views/Timeline/GroupNarrativeCard.swift` ファイル作成
- [ ] 要約テキスト表示
- [ ] ハイライト表示

### 2.9.4 展開/折りたたみアニメーション
- [ ] withAnimation(.spring)
- [ ] isExpanded状態管理

### 2.9.5 コミット数制限
- [ ] 最初の10件表示
- [ ] "+N more commits" ボタン

---

## 2.10 UI - プロジェクトストーリー

### 2.10.1 ProjectStoryView 基本
- [ ] `Views/Story/ProjectStoryView.swift` ファイル作成
- [ ] ストーリーあり: StoryContent表示
- [ ] ストーリーなし: EmptyStoryView表示

### 2.10.2 EmptyStoryView
- [ ] `Views/Story/EmptyStoryView.swift` ファイル作成
- [ ] ContentUnavailableView
- [ ] "Generate Story" ボタン
- [ ] 生成中プログレス

### 2.10.3 StoryContent
- [ ] `Views/Story/StoryContent.swift` ファイル作成
- [ ] tagline表示 (イタリック)
- [ ] Originセクション
- [ ] Evolutionセクション
- [ ] Philosophyセクション
- [ ] Challengesセクション
- [ ] Milestonesセクション

### 2.10.4 StorySection コンポーネント
- [ ] `Views/Story/StorySection.swift` ファイル作成
- [ ] タイトル + コンテンツ

### 2.10.5 MilestonesSection コンポーネント
- [ ] `Views/Story/MilestonesSection.swift` ファイル作成
- [ ] バージョンバッジ + 説明

---

## 2.11 UI - 要約生成進捗

### 2.11.1 SummaryProgress 列挙型
- [ ] `enum SummaryProgress`
- [ ] case: commits(current, total)
- [ ] case: groups(current, total)
- [ ] case: versions(current, total)
- [ ] case: projectStory

### 2.11.2 進捗表示UI
- [ ] ProgressView with value
- [ ] 現在のフェーズ表示
- [ ] キャンセルボタン

### 2.11.3 AppViewModel 進捗管理
- [ ] `@Published var summaryProgress: SummaryProgress?`
- [ ] 生成中フラグ

---

## 2.12 UI - 詳細ビュー AI要約

### 2.12.1 AISummarySection
- [ ] `Views/Detail/AISummarySection.swift` ファイル作成
- [ ] 要約あり: テキスト表示
- [ ] 要約なし: "Generate" ボタン
- [ ] 生成中: ProgressView

### 2.12.2 KeywordsSection
- [ ] `Views/Detail/KeywordsSection.swift` ファイル作成
- [ ] FlowLayout
- [ ] キーワードタグ

### 2.12.3 ImpactBadge
- [ ] `Views/Components/ImpactBadge.swift` ファイル作成
- [ ] impact別色

### 2.12.4 CategoryBadge
- [ ] `Views/Components/CategoryBadge.swift` ファイル作成
- [ ] アイコン + ラベル

---

## 2.13 Anthropic対応

### 2.13.1 AnthropicProvider 基本
- [ ] `Services/AI/AnthropicProvider.swift` ファイル作成
- [ ] `final class AnthropicProvider: AIProvider`
- [ ] プロパティ: apiKey, model

### 2.13.2 AnthropicProvider - complete
- [ ] URL: `https://api.anthropic.com/v1/messages`
- [ ] x-api-key ヘッダー
- [ ] anthropic-version ヘッダー
- [ ] リクエストボディ構築
- [ ] レスポンスパース

### 2.13.3 AnthropicSettings
- [ ] `Views/Settings/AnthropicSettings.swift` ファイル作成
- [ ] APIキー設定
- [ ] モデル選択 (claude-3-opus, sonnet, haiku)

### 2.13.4 Settings - プロバイダー切替
- [ ] switch文でプロバイダー別設定表示

### 2.13.5 AppViewModel - プロバイダー生成
- [ ] 設定に基づいてAIProvider生成
- [ ] Keychain からAPIキー取得

---

## 2.14 検索機能

### 2.14.1 TimelineView 検索
- [ ] `@State private var searchText: String`
- [ ] `.searchable()` 修飾子

### 2.14.2 検索フィルタリング
- [ ] コミットメッセージで検索
- [ ] 要約テキストで検索
- [ ] 作者名で検索

---

# Phase 3: Release（リリース準備）

## 3.1 Ollama対応

### 3.1.1 OllamaProvider 基本
- [ ] `Services/AI/OllamaProvider.swift` ファイル作成
- [ ] `final class OllamaProvider: AIProvider`
- [ ] プロパティ: host, port, model

### 3.1.2 OllamaProvider - complete
- [ ] URL構築: `http://{host}:{port}/api/generate`
- [ ] リクエストボディ (model, prompt, stream: false, format: json)
- [ ] レスポンスパース

### 3.1.3 OllamaProvider - isAvailable
- [ ] `/api/tags` エンドポイント確認
- [ ] HTTPステータス200チェック

### 3.1.4 OllamaProvider - モデル一覧
- [ ] `func fetchAvailableModels() async throws -> [String]`
- [ ] /api/tags レスポンスパース

### 3.1.5 OllamaSettings
- [ ] `Views/Settings/OllamaSettings.swift` ファイル作成
- [ ] ホスト入力 TextField
- [ ] ポート入力 TextField
- [ ] モデル選択 Picker
- [ ] 接続テストボタン
- [ ] 接続ステータス表示

### 3.1.6 Ollama接続テスト
- [ ] isAvailable呼び出し
- [ ] ConnectionStatus更新
- [ ] エラーメッセージ表示

### 3.1.7 モデルリスト動的取得
- [ ] 接続成功時にモデル取得
- [ ] Picker選択肢更新

---

## 3.2 エラーハンドリング強化

### 3.2.1 GitTaleError 統合
- [ ] `Utilities/GitTaleError.swift` ファイル作成
- [ ] 全エラーケース定義
- [ ] LocalizedError準拠
- [ ] recoverySuggestion提供

### 3.2.2 エラーアラート
- [ ] `.alert()` 修飾子
- [ ] エラータイトル
- [ ] エラーメッセージ
- [ ] 回復提案

### 3.2.3 ネットワークエラー
- [ ] タイムアウト処理
- [ ] リトライロジック
- [ ] オフライン検出

### 3.2.4 Gitエラー
- [ ] リポジトリ無効
- [ ] コマンド失敗
- [ ] パーミッション問題

### 3.2.5 AIエラー
- [ ] APIキー無効
- [ ] レート制限
- [ ] レスポンスパース失敗

---

## 3.3 パフォーマンス最適化

### 3.3.1 LazyVStack最適化
- [ ] id明示指定
- [ ] 不要な再描画防止

### 3.3.2 コミット読み込み最適化
- [ ] 初期表示は最新1000件
- [ ] スクロールで追加読み込み
- [ ] または全件一括（大規模対応）

### 3.3.3 Diff統計遅延取得
- [ ] 表示時に取得
- [ ] キャッシュ

### 3.3.4 バックグラウンド処理
- [ ] Task.detached使用
- [ ] UI応答性維持
- [ ] キャンセル対応

### 3.3.5 メモリ管理
- [ ] 大規模リポジトリプロファイリング
- [ ] 不要データ解放
- [ ] weak参照適切使用

---

## 3.4 アクセシビリティ

### 3.4.1 VoiceOver ラベル
- [ ] 全インタラクティブ要素にラベル
- [ ] CommitRow: 要約 + メタデータ読み上げ
- [ ] ボタン: アクション説明

### 3.4.2 VoiceOver ヒント
- [ ] accessibilityHint追加
- [ ] 操作方法説明

### 3.4.3 VoiceOver グループ化
- [ ] 関連要素をグループ化
- [ ] accessibilityElement(children:)

### 3.4.4 Dynamic Type
- [ ] .font(.body)等の動的フォント使用
- [ ] 拡大表示テスト

### 3.4.5 カラーコントラスト
- [ ] WCAG準拠確認
- [ ] ハイコントラストモード

---

## 3.5 ローカライゼーション

### 3.5.1 Localizable.strings (日本語)
- [ ] ファイル作成
- [ ] 全UI文字列抽出
- [ ] 翻訳追加

### 3.5.2 Localizable.strings (英語)
- [ ] ファイル作成
- [ ] デフォルト英語文字列

### 3.5.3 String Catalog
- [ ] Xcode String Catalog使用検討
- [ ] 複数形対応

### 3.5.4 日付/数値フォーマット
- [ ] ロケール対応フォーマッター使用
- [ ] .formatted() API活用

---

## 3.6 ダークモード

### 3.6.1 カラーアセット
- [ ] Assets.xcassets にカラーセット追加
- [ ] Light/Dark対応

### 3.6.2 システムカラー使用
- [ ] Color.primary, .secondary等
- [ ] NSColor.windowBackgroundColor等

### 3.6.3 アイコンカラー
- [ ] SF Symbolのカラー対応
- [ ] .foregroundStyle使用

### 3.6.4 テスト
- [ ] ライトモード確認
- [ ] ダークモード確認
- [ ] 切替時の表示確認

---

## 3.7 App Store準備

### 3.7.1 アプリアイコン
- [ ] 1024x1024 デザイン作成
- [ ] 各サイズ生成 (16, 32, 64, 128, 256, 512, 1024)
- [ ] Assets.xcassets追加

### 3.7.2 スクリーンショット
- [ ] メイン画面 (タイムライン)
- [ ] プロジェクトストーリー画面
- [ ] 詳細画面
- [ ] 設定画面
- [ ] ダークモード版

### 3.7.3 App Store説明文
- [ ] タイトル (30文字以内)
- [ ] サブタイトル
- [ ] 説明文 (日本語)
- [ ] 説明文 (英語)
- [ ] キーワード

### 3.7.4 プライバシーポリシー
- [ ] データ収集内容記載
- [ ] AIへの送信内容説明
- [ ] ホスティング (GitHub Pages等)

### 3.7.5 Sandbox設定
- [ ] App Sandbox有効化
- [ ] ファイルアクセス権限
- [ ] ネットワーク権限

### 3.7.6 署名・証明書
- [ ] Developer ID証明書
- [ ] Provisioning Profile
- [ ] Notarization

### 3.7.7 TestFlight
- [ ] TestFlightビルド
- [ ] 内部テスター招待
- [ ] ベータフィードバック収集

### 3.7.8 App Store Connect
- [ ] アプリ登録
- [ ] メタデータ入力
- [ ] ビルドアップロード
- [ ] 審査提出

---

## チェックリスト総括

### Phase 1 完了条件
- [ ] リポジトリをドラッグ&ドロップで開ける
- [ ] コミット一覧が時系列で表示される
- [ ] コミット選択で詳細表示
- [ ] OpenAI APIキーを設定できる
- [ ] 単一コミットの要約を生成できる

### Phase 2 完了条件
- [ ] 要約が.gittale/cache/にキャッシュされる
- [ ] ズームレベルで表示粒度変更可能
- [ ] グループ要約が物語形式で表示
- [ ] プロジェクトストーリー生成可能
- [ ] Anthropic Claudeで要約生成可能

### Phase 3 完了条件
- [ ] Ollamaでローカル要約生成可能
- [ ] 大規模リポジトリ(10万コミット)でスムーズ動作
- [ ] VoiceOverで操作可能
- [ ] 日英対応
- [ ] App Store審査提出完了
