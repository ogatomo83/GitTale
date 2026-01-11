//
//  Repository.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import Foundation

/// リポジトリ情報
struct Repository: Identifiable, Hashable, Codable {
    let id: UUID
    let owner: String
    let name: String
    let url: String
    let clonedAt: Date

    init(id: UUID = UUID(), owner: String, name: String, url: String, clonedAt: Date = Date()) {
        self.id = id
        self.owner = owner
        self.name = name
        self.url = url
        self.clonedAt = clonedAt
    }

    /// 表示用の名前（owner/name）
    var displayName: String {
        "\(owner)/\(name)"
    }
}

// MARK: - Repository Storage

/// リポジトリの永続化を管理
actor RepositoryStorage {
    static let shared = RepositoryStorage()

    private let settings = AppSettings.shared

    private init() {}

    // MARK: - Save

    /// リポジトリのメタデータをJSONファイルに保存
    func save(_ repository: Repository) throws {
        let metadataURL = settings.repositoryMetadataURL(owner: repository.owner, name: repository.name)

        // ディレクトリが存在しない場合は作成
        let directory = metadataURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(repository)
        try data.write(to: metadataURL)
    }

    // MARK: - Load

    /// 全てのリポジトリを読み込む
    func loadAll() throws -> [Repository] {
        let repositoriesDir = settings.repositoriesDirectoryURL
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: repositoriesDir.path) else {
            return []
        }

        var repositories: [Repository] = []

        // owner ディレクトリを列挙
        let ownerDirs = try fileManager.contentsOfDirectory(at: repositoriesDir, includingPropertiesForKeys: nil)

        for ownerDir in ownerDirs {
            guard ownerDir.hasDirectoryPath else { continue }

            // name ディレクトリを列挙
            let nameDirs = try fileManager.contentsOfDirectory(at: ownerDir, includingPropertiesForKeys: nil)

            for nameDir in nameDirs {
                guard nameDir.hasDirectoryPath else { continue }

                // {name}.json を探す
                let jsonFile = nameDir.appendingPathComponent("\(nameDir.lastPathComponent).json")

                if fileManager.fileExists(atPath: jsonFile.path) {
                    if let repo = try? loadRepository(from: jsonFile) {
                        repositories.append(repo)
                    }
                }
            }
        }

        return repositories.sorted { $0.clonedAt > $1.clonedAt }
    }

    /// 特定のJSONファイルからリポジトリを読み込む
    private func loadRepository(from url: URL) throws -> Repository {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Repository.self, from: data)
    }

    // MARK: - Delete

    /// リポジトリを削除
    func delete(_ repository: Repository) throws {
        let repoDir = settings.repositoryDirectoryURL(owner: repository.owner, name: repository.name)
        try FileManager.default.removeItem(at: repoDir)
    }

    // MARK: - Check

    /// リポジトリが既に存在するか確認
    func exists(owner: String, name: String) -> Bool {
        let sourceDir = settings.repositorySourceURL(owner: owner, name: name)
        return FileManager.default.fileExists(atPath: sourceDir.path)
    }
}
