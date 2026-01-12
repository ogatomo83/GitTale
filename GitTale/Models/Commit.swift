//
//  Commit.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import Foundation

/// Gitコミット情報
struct Commit: Identifiable, Hashable {
    let sha: String
    let shortSHA: String
    let author: String
    let email: String
    let date: Date
    let message: String
    let parentSHAs: [String]

    var id: String { sha }

    /// コミットメッセージの1行目
    var subject: String {
        message.components(separatedBy: "\n").first ?? message
    }

    /// マージコミットかどうか
    var isMergeCommit: Bool {
        parentSHAs.count > 1
    }
}

/// リポジトリの進捗状況
struct RepositoryProgress: Codable {
    var checkedCommitSHAs: Set<String>
    var lastUpdated: Date

    init(checkedCommitSHAs: Set<String> = [], lastUpdated: Date = Date()) {
        self.checkedCommitSHAs = checkedCommitSHAs
        self.lastUpdated = lastUpdated
    }

    /// コミットが確認済みかどうか
    func isChecked(_ sha: String) -> Bool {
        checkedCommitSHAs.contains(sha)
    }

    /// 確認状況をトグル
    mutating func toggle(_ sha: String) {
        if checkedCommitSHAs.contains(sha) {
            checkedCommitSHAs.remove(sha)
        } else {
            checkedCommitSHAs.insert(sha)
        }
        lastUpdated = Date()
    }
}

// MARK: - Commit Cache

/// コミットSHAリストのキャッシュ
struct CommitCache: Codable {
    var shas: [String]
    var lastUpdated: Date

    init(shas: [String] = [], lastUpdated: Date = Date()) {
        self.shas = shas
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Commit Storage

/// コミットSHAリストの永続化
actor CommitStorage {
    static let shared = CommitStorage()

    private let settings = AppSettings.shared

    private init() {}

    /// キャッシュファイルのパス
    private func cacheURL(owner: String, name: String) -> URL {
        settings.repositoryDirectoryURL(owner: owner, name: name)
            .appendingPathComponent("commits.json")
    }

    /// キャッシュを読み込む
    func loadCache(owner: String, name: String) throws -> CommitCache? {
        let url = cacheURL(owner: owner, name: name)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[CommitStorage] キャッシュなし")
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cache = try decoder.decode(CommitCache.self, from: data)
        print("[CommitStorage] キャッシュ読み込み: \(cache.shas.count)件")
        return cache
    }

    /// キャッシュを保存
    func saveCache(_ cache: CommitCache, owner: String, name: String) throws {
        let url = cacheURL(owner: owner, name: name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(cache)
        try data.write(to: url)
        print("[CommitStorage] キャッシュ保存: \(cache.shas.count)件")
    }

    /// キャッシュを更新（差分追加）
    func appendToCache(newSHAs: [String], owner: String, name: String) throws {
        var cache = (try? loadCache(owner: owner, name: name)) ?? CommitCache()
        cache.shas.append(contentsOf: newSHAs)
        cache.lastUpdated = Date()
        try saveCache(cache, owner: owner, name: name)
    }
}

// MARK: - Progress Storage

/// 進捗状況の永続化
actor ProgressStorage {
    static let shared = ProgressStorage()

    private let settings = AppSettings.shared

    private init() {}

    /// 進捗ファイルのパス
    private func progressURL(owner: String, name: String) -> URL {
        settings.repositoryDirectoryURL(owner: owner, name: name)
            .appendingPathComponent("progress.json")
    }

    /// 進捗を読み込む
    func load(owner: String, name: String) throws -> RepositoryProgress {
        let url = progressURL(owner: owner, name: name)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return RepositoryProgress()
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RepositoryProgress.self, from: data)
    }

    /// 進捗を保存
    func save(_ progress: RepositoryProgress, owner: String, name: String) throws {
        let url = progressURL(owner: owner, name: name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(progress)
        try data.write(to: url)
    }
}
