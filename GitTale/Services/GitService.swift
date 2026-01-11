//
//  GitService.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import Foundation

/// Gitコマンドを実行するサービス
actor GitService {
    static let shared = GitService()

    private init() {}

    // MARK: - Clone

    /// リポジトリをクローンする
    /// - Parameters:
    ///   - url: リポジトリURL
    ///   - destination: クローン先ディレクトリ
    /// - Returns: 成功時はtrue
    func clone(url: String, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", url, destination.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.cloneFailed(errorMessage)
        }
    }

    // MARK: - Repository Validation

    /// URLからリポジトリ情報を解析
    /// - Parameter url: リポジトリURL (例: https://github.com/owner/repo.git)
    /// - Returns: (owner, name) のタプル
    func parseRepositoryURL(_ url: String) throws -> (owner: String, name: String) {
        // GitHub, GitLab, Bitbucket などに対応
        // 形式: https://github.com/owner/repo.git または git@github.com:owner/repo.git

        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // .git 拡張子を削除
        let withoutGit = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed

        // HTTPS形式: https://github.com/owner/repo
        if withoutGit.contains("://") {
            let components = withoutGit.components(separatedBy: "/")
            guard components.count >= 2 else {
                throw GitError.invalidURL(url)
            }
            let name = components.last ?? ""
            let owner = components.dropLast().last ?? ""

            guard !owner.isEmpty, !name.isEmpty else {
                throw GitError.invalidURL(url)
            }
            return (owner, name)
        }

        // SSH形式: git@github.com:owner/repo
        if withoutGit.contains("@") && withoutGit.contains(":") {
            let afterColon = withoutGit.components(separatedBy: ":").last ?? ""
            let parts = afterColon.components(separatedBy: "/")
            guard parts.count >= 2 else {
                throw GitError.invalidURL(url)
            }
            let owner = parts[0]
            let name = parts[1]

            guard !owner.isEmpty, !name.isEmpty else {
                throw GitError.invalidURL(url)
            }
            return (owner, name)
        }

        throw GitError.invalidURL(url)
    }
}

// MARK: - Errors

enum GitError: LocalizedError {
    case cloneFailed(String)
    case invalidURL(String)
    case notARepository
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .cloneFailed(let message):
            return "Clone failed: \(message)"
        case .invalidURL(let url):
            return "Invalid repository URL: \(url)"
        case .notARepository:
            return "Not a Git repository"
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        }
    }
}
