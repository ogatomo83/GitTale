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

    // MARK: - Commit History

    /// コミットSHAリストを取得（軽量・高速）- 全件取得
    func getCommitSHAs(at repositoryPath: URL) async throws -> [String] {
        print("[GitService] コミットSHAリストを取得中...")
        print("[GitService] リポジトリパス: \(repositoryPath.path)")
        let startTime = Date()

        print("[GitService] executeを呼び出し中...")
        let output = try await execute(
            ["rev-list", "--reverse", "HEAD"],
            at: repositoryPath
        )
        print("[GitService] execute完了、出力長: \(output.count)文字")

        let shas = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        let elapsed = Date().timeIntervalSince(startTime)
        print("[GitService] \(shas.count)件のコミットSHAを取得完了 (\(String(format: "%.2f", elapsed))秒)")

        return shas
    }

    /// 差分コミットSHAを取得（lastSHA以降の新しいコミット）
    func getNewCommitSHAs(since lastSHA: String, at repositoryPath: URL) async throws -> [String] {
        print("[GitService] 差分コミットを取得中 (since: \(lastSHA.prefix(8))...)...")
        let startTime = Date()

        let output = try await execute(
            ["rev-list", "--reverse", "\(lastSHA)..HEAD"],
            at: repositoryPath
        )

        let shas = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        let elapsed = Date().timeIntervalSince(startTime)
        print("[GitService] \(shas.count)件の新規コミットを取得完了 (\(String(format: "%.2f", elapsed))秒)")

        return shas
    }

    /// 最初のN件のコミットSHAを取得（古い順）
    func getFirstCommitSHAs(count: Int, at repositoryPath: URL) async throws -> [String] {
        print("[GitService] 最初の\(count)件のコミットSHAを取得中（古い順）...")
        let startTime = Date()

        // git rev-list --reverse HEAD で全件を古い順に取得し、最初のN件を返す
        // --max-count と --reverse の組み合わせは「最新N件を逆順」になるため使わない
        let output = try await execute(
            ["rev-list", "--reverse", "HEAD"],
            at: repositoryPath
        )

        let allSHAs = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let shas = Array(allSHAs.prefix(count))

        let elapsed = Date().timeIntervalSince(startTime)
        print("[GitService] 全\(allSHAs.count)件中、最初の\(shas.count)件を取得完了 (\(String(format: "%.2f", elapsed))秒)")

        return shas
    }

    /// 特定のコミットの詳細情報を取得
    func getCommitDetail(sha: String, at repositoryPath: URL) async throws -> Commit {
        print("[GitService] コミット詳細を取得中: \(sha.prefix(8))...")

        let output = try await execute(
            ["log", "-1", "--format=%H|%h|%an|%ae|%aI|%B|%P", sha],
            at: repositoryPath
        )

        guard let commit = parseCommitLine(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GitError.commandFailed("Failed to parse commit: \(sha)")
        }

        print("[GitService] コミット詳細取得完了: \(commit.subject.prefix(30))...")
        return commit
    }

    /// 複数コミットの詳細を一括取得（バッチ）
    func getCommitDetails(shas: [String], at repositoryPath: URL) async throws -> [Commit] {
        print("[GitService] \(shas.count)件のコミット詳細を取得中...")
        let startTime = Date()

        // 一括でログを取得
        let shaList = shas.joined(separator: "\n")
        let output = try await execute(
            ["log", "--stdin", "--no-walk", "--format=%H|%h|%an|%ae|%aI|%s|%P"],
            at: repositoryPath,
            input: shaList
        )

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let commits = lines.compactMap { parseCommitLine($0) }

        let elapsed = Date().timeIntervalSince(startTime)
        print("[GitService] \(commits.count)件のコミット詳細を取得完了 (\(String(format: "%.2f", elapsed))秒)")

        // SHA順序を維持するためにソート
        let shaOrder = Dictionary(uniqueKeysWithValues: shas.enumerated().map { ($1, $0) })
        return commits.sorted { (shaOrder[$0.sha] ?? 0) < (shaOrder[$1.sha] ?? 0) }
    }

    /// コミット行をパース
    private func parseCommitLine(_ line: String) -> Commit? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 6 else { return nil }

        let sha = parts[0]
        let shortSHA = parts[1]
        let author = parts[2]
        let email = parts[3]
        let dateString = parts[4]
        let message = parts[5]
        let parentSHAs = parts.count > 6 ? parts[6].components(separatedBy: " ").filter { !$0.isEmpty } : []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: dateString) else { return nil }

        return Commit(
            sha: sha,
            shortSHA: shortSHA,
            author: author,
            email: email,
            date: date,
            message: message,
            parentSHAs: parentSHAs
        )
    }

    // MARK: - Checkout

    /// 特定のコミットにチェックアウト
    func checkout(sha: String, at repositoryPath: URL) async throws {
        print("[GitService] チェックアウト中: \(sha.prefix(8))...")
        _ = try await execute(["checkout", sha], at: repositoryPath)
        print("[GitService] チェックアウト完了")
    }

    /// デフォルトブランチ（main/master）にチェックアウト
    func checkoutDefaultBranch(at repositoryPath: URL) async throws {
        print("[GitService] デフォルトブランチを検索中...")

        // リモートのデフォルトブランチを取得
        let output = try await execute(
            ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
            at: repositoryPath
        )
        let defaultBranch = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "origin/", with: "")

        print("[GitService] デフォルトブランチ: \(defaultBranch)")
        _ = try await execute(["checkout", defaultBranch], at: repositoryPath)
        print("[GitService] チェックアウト完了")
    }

    // MARK: - Fetch

    /// リモートから最新を取得
    func fetch(at repositoryPath: URL) async throws {
        print("[GitService] fetch中...")
        _ = try await execute(["fetch", "origin"], at: repositoryPath)
        print("[GitService] fetch完了")
    }

    /// リモートから最新を取得してマージ
    func pull(at repositoryPath: URL) async throws {
        print("[GitService] pull中...")
        _ = try await execute(["pull", "origin"], at: repositoryPath)
        print("[GitService] pull完了")
    }

    // MARK: - Diff

    /// 変更されたファイル一覧を取得（1コミット）
    func getChangedFiles(sha: String, at repositoryPath: URL) async throws -> [ChangedFile] {
        print("[GitService] 変更ファイル一覧を取得中: \(sha.prefix(8))...")

        let output = try await execute(
            ["diff-tree", "--no-commit-id", "--name-status", "-r", sha],
            at: repositoryPath
        )

        let files = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> ChangedFile? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { return nil }
                let status = ChangeStatus(rawValue: String(parts[0].prefix(1))) ?? .modified
                let path = parts[1]
                return ChangedFile(path: path, status: status)
            }

        print("[GitService] \(files.count)件の変更ファイルを取得")
        return files
    }

    /// 変更されたファイル一覧を取得（2コミット間）
    func getChangedFilesBetween(from fromSHA: String, to toSHA: String, at repositoryPath: URL) async throws -> [ChangedFile] {
        print("[GitService] 変更ファイル一覧を取得中: \(fromSHA.prefix(8))..\(toSHA.prefix(8))...")

        let output = try await execute(
            ["diff", "--name-status", fromSHA, toSHA],
            at: repositoryPath
        )

        let files = output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> ChangedFile? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { return nil }
                let status = ChangeStatus(rawValue: String(parts[0].prefix(1))) ?? .modified
                let path = parts[1]
                return ChangedFile(path: path, status: status)
            }

        print("[GitService] \(files.count)件の変更ファイルを取得")
        return files
    }

    /// ファイルの差分を取得（1コミット）
    func getFileDiff(sha: String, filePath: String, at repositoryPath: URL) async throws -> String {
        print("[GitService] ファイル差分を取得中: \(filePath)")

        let output = try await execute(
            ["show", "--format=", sha, "--", filePath],
            at: repositoryPath
        )

        return output
    }

    /// ファイルの差分を取得（2コミット間）
    func getFileDiffBetween(from fromSHA: String, to toSHA: String, filePath: String, at repositoryPath: URL) async throws -> String {
        print("[GitService] ファイル差分を取得中: \(filePath) (\(fromSHA.prefix(8))..\(toSHA.prefix(8)))")

        let output = try await execute(
            ["diff", fromSHA, toSHA, "--", filePath],
            at: repositoryPath
        )

        return output
    }

    /// ファイルの内容を取得
    func getFileContent(sha: String, filePath: String, at repositoryPath: URL) async throws -> String {
        print("[GitService] ファイル内容を取得中: \(filePath) @ \(sha.prefix(8))")

        let output = try await execute(
            ["show", "\(sha):\(filePath)"],
            at: repositoryPath
        )

        return output
    }

    // MARK: - File Tree

    /// リポジトリ内の全ファイルパスを取得
    func getAllFilePaths(sha: String, at repositoryPath: URL) async throws -> [String] {
        print("[GitService] ファイルツリーを取得中: \(sha.prefix(8))...")

        let output = try await execute(
            ["ls-tree", "-r", "--name-only", sha],
            at: repositoryPath
        )

        let files = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        print("[GitService] \(files.count)件のファイルを取得")
        return files
    }

    // MARK: - Git Command Execution

    /// Gitコマンドを実行
    private func execute(_ arguments: [String], at repositoryPath: URL, input: String? = nil) async throws -> String {
        print("[GitService.execute] 開始: git \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryPath

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // 標準入力が必要な場合のみパイプを設定
        let stdin: Pipe?
        if let input = input {
            stdin = Pipe()
            process.standardInput = stdin
        } else {
            stdin = nil
        }

        print("[GitService.execute] process.run()を呼び出し中...")
        try process.run()
        print("[GitService.execute] process.run()完了")

        // 標準入力にデータを書き込む
        if let input = input, let stdinPipe = stdin {
            print("[GitService.execute] 標準入力に書き込み中...")
            stdinPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
            stdinPipe.fileHandleForWriting.closeFile()
            print("[GitService.execute] 標準入力書き込み完了")
        }

        // 重要: 大量の出力がある場合、パイプのバッファがいっぱいになりデッドロックする
        // waitUntilExit()の前に標準出力を読み取る必要がある
        print("[GitService.execute] 標準出力を読み取り中...")
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        print("[GitService.execute] 読み取り完了、データサイズ: \(outputData.count)バイト")

        print("[GitService.execute] waitUntilExit()を呼び出し中...")
        process.waitUntilExit()
        print("[GitService.execute] waitUntilExit()完了、終了ステータス: \(process.terminationStatus)")

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("[GitService.execute] エラー: \(errorMessage)")
            throw GitError.commandFailed(errorMessage)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
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
