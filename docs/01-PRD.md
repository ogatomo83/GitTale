# GitTale - 要件定義書（PRD）

## 1. プロダクト概要

### 1.1 プロダクト名
**GitTale** - Git Repository Story Visualizer

### 1.2 ビジョン
「コードの歴史を、物語として読む」

Gitリポジトリのコミットログを、AIの力で意味のある「開発ドキュメンタリー」に変換するmacOSネイティブアプリケーション。

### 1.3 設計思想

**Gitが唯一の真実（Single Source of Truth）**

```
┌────────────────────────────────────────────────────┐
│                    データ戦略                       │
├────────────────────────────────────────────────────┤
│                                                    │
│  .git/           ← 唯一のデータソース（読み取り専用）│
│    │                                               │
│    ├── コミット情報  → 毎回取得（git log）          │
│    ├── タグ情報      → 毎回取得（git tag）          │
│    └── Diff統計      → 毎回取得（git diff）         │
│                                                    │
│  .gittale/       ← AI要約キャッシュのみ保存         │
│    └── cache/                                      │
│        └── {sha}.json                              │
│                                                    │
│  ※ DBは持たない。アプリを軽量・シンプルに保つ       │
│                                                    │
└────────────────────────────────────────────────────┘
```

### 1.4 ターゲットユーザー

| ペルソナ | ニーズ | 利用シーン |
|---------|--------|-----------|
| **OSS学習者** | 有名OSSの設計思想・アーキテクチャ変遷を学びたい | React, Vue, Rustなどのリポジトリを解析 |
| **新規参画エンジニア** | 既存プロジェクトの歴史的経緯を把握したい | チーム参加時の背景理解 |
| **メンテナー** | 大規模コードベースの変更履歴を俯瞰したい | リファクタリング判断材料 |
| **テックライター** | 技術ドキュメントやブログ記事の素材収集 | OSS歴史の記事化 |

---

## 2. 機能要件

### 2.1 MV（Minimum Viable）機能

#### FR-001: リポジトリ操作
- **FR-001-01**: ローカルGitリポジトリをドラッグ&ドロップで開く
- **FR-001-02**: 最近開いたリポジトリの履歴表示（UserDefaults）
- **FR-001-03**: `git log --reverse --all` でコミット履歴取得
- **FR-001-04**: `git checkout` で任意のコミットに移動（読み取り専用モード）

#### FR-002: コミット解析
- **FR-002-01**: `git log --format` でコミット情報抽出（SHA, Author, Date, Message, Parents）
- **FR-002-02**: `git diff --stat` で変更統計取得
- **FR-002-03**: `git tag -l` でタグ情報取得
- **FR-002-04**: マージコミットの検出（親が2つ以上）

#### FR-003: AI要約生成
- **FR-003-01**: 単一コミットの要約（コミットメッセージ + Diff統計から推論）
- **FR-003-02**: コミットグループの要約（時間/タグベースでグルーピング）
- **FR-003-03**: バージョン間サマリー生成
- **FR-003-04**: プロジェクト全体のストーリー生成
- **FR-003-05**: `.gittale/cache/` に要約をJSONキャッシュ（SHA単位）

#### FR-004: タイムラインビュー
- **FR-004-01**: 時系列でコミット/要約を表示
- **FR-004-02**: ズームレベル切替（日/週/月/バージョン）
- **FR-004-03**: コミット詳細へのドリルダウン
- **FR-004-04**: 期間フィルタリング

#### FR-005: 設定
- **FR-005-01**: AI Provider選択（OpenAI / Anthropic / Ollama / MLX）
- **FR-005-02**: APIキーのKeychain保存
- **FR-005-03**: ローカルLLM接続設定
- **FR-005-04**: 出力言語設定（日本語/英語）

### 2.2 拡張機能（将来）

- コントリビューター分析
- ホットスポット検出（頻繁に変更されるファイル）
- 検索機能（要約内キーワード検索）
- エクスポート（Markdown / PDF）
- GitHub/GitLab連携（Issue/PR紐付け）

---

## 3. 非機能要件

### 3.1 パフォーマンス
| 項目 | 目標値 |
|------|--------|
| 10,000コミットのリポジトリ読み込み | 3秒以内 |
| タイムライン初期レンダリング | 500ms以内 |
| スクロール時のフレームレート | 60fps維持 |
| メモリ使用量（100,000コミット時） | 300MB以下 |

### 3.2 セキュリティ
- APIキーはmacOS Keychainに保存
- AIへの送信データは最小限（フルソースコードは送信しない）
- リポジトリは読み取り専用で操作

### 3.3 互換性
- macOS 14.0 (Sonoma) 以上
- Apple Silicon (M1/M2/M3/M4) ネイティブ対応
- Intel Mac対応（ローカルLLMは非推奨）

---

## 4. 技術的課題への解決策

### 4.1 トークン制限とコスト

#### グルーピング戦略

```
[Raw Commits]
    │
    ├── タグベース ──→ v1.0...v1.1 の範囲でグループ化
    │
    ├── 時間ベース ──→ 週単位/月単位でバッチ
    │
    └── 意味ベース ──→ 同一Author連続コミット
                       同一ファイル群への変更
```

**重要度フィルタリング**:
- High: `BREAKING CHANGE`, `feat:`, 500行以上の変更 → 個別要約
- Medium: `fix:`, `perf:` → グループ要約
- Low: `style:`, `chore:`, typo修正 → 集約のみ

### 4.2 階層的要約

```
Level 0: Individual Commit
    ↓ (10-20 commits)
Level 1: Group Summary
    ↓ (4-8 groups)
Level 2: Version Summary
    ↓ (all versions)
Level 3: Project Story
```

Map-Reduceパターンで段階的に集約。

### 4.3 Diff解析による変更種別判定

| 種別 | 判定ロジック |
|------|-------------|
| **Feature** | 新規ファイル追加 + 追加行 > 削除行 |
| **Fix** | 変更行少数 + テストファイル変更なし |
| **Refactor** | 追加行 ≈ 削除行 + 同一ファイル内変更 |
| **Test** | test/spec ディレクトリ内のみ |
| **Docs** | .md/.txt/docs/ のみ |

**AIには統計情報のみ送信**:
```swift
struct DiffMetadata {
    let filesChanged: [String]
    let additions: Int
    let deletions: Int
    let fileTypes: [String: Int]  // 拡張子別カウント
}
```

---

## 5. キャッシュ戦略

### 5.1 ディレクトリ構造

```
/path/to/repository/
├── .git/                    # Git本体（読み取りのみ）
├── .gittale/                # GitTaleキャッシュ
│   ├── .gitignore           # "**" で全体を無視
│   └── cache/
│       ├── commits/
│       │   ├── abc1234.json # 個別コミット要約
│       │   └── def5678.json
│       ├── groups/
│       │   └── 2024-w03.json # 週間グループ要約
│       ├── versions/
│       │   └── v1.0.0.json  # バージョン要約
│       └── story.json       # プロジェクト全体ストーリー
└── src/                     # 実際のソースコード
```

### 5.2 キャッシュ無効化

```swift
// キャッシュが有効かどうかの判定
func isCacheValid(sha: String) -> Bool {
    // SHAが一致すれば内容は不変（Gitの性質）
    return cacheExists(for: sha)
}

// グループ/バージョンキャッシュは新規コミット追加時に無効化
func invalidateGroupCache(after date: Date) {
    // 指定日以降のグループキャッシュを削除
}
```

### 5.3 .gitignore自動生成

```swift
func ensureGitIgnore(in gittaleDir: URL) {
    let gitignorePath = gittaleDir.appendingPathComponent(".gitignore")
    if !FileManager.default.fileExists(atPath: gitignorePath.path) {
        try? "# GitTale cache - do not commit\n**".write(to: gitignorePath, atomically: true, encoding: .utf8)
    }
}
```

---

## 6. 制約事項

### 6.1 スコープ内
- ローカルGitリポジトリの解析
- AI要約の生成とキャッシュ
- 読み取り専用の履歴閲覧

### 6.2 スコープ外
- リモートリポジトリの直接クローン
- コード編集・コミット作成
- Windows/Linux対応
- リアルタイムコラボレーション
