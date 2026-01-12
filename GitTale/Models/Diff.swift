//
//  Diff.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/12.
//

import SwiftUI

// MARK: - File Tree Node

/// ファイルツリーのノード
class FileTreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var changeStatus: ChangeStatus?
    @Published var children: [FileTreeNode]
    @Published var isExpanded: Bool

    init(name: String, path: String, isDirectory: Bool, children: [FileTreeNode] = []) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = false
        self.changeStatus = nil
    }

    /// フラットなファイルパスリストからツリーを構築
    static func buildTree(from paths: [String], changedFiles: [ChangedFile] = []) -> [FileTreeNode] {
        // 変更ステータスのマップ
        let changedPathsStatus = Dictionary(uniqueKeysWithValues: changedFiles.map { ($0.path, $0.status) })

        // ルートレベルのノードマップ
        var rootNodes: [String: FileTreeNode] = [:]

        for path in paths {
            let components = path.components(separatedBy: "/")
            var currentNodes = rootNodes
            var currentPath = ""
            var parentNode: FileTreeNode?

            for (index, component) in components.enumerated() {
                let isLast = index == components.count - 1
                currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"

                // 既存ノードを探すか、新規作成
                let node: FileTreeNode
                if let existingNode = currentNodes[component] {
                    node = existingNode
                } else {
                    node = FileTreeNode(
                        name: component,
                        path: currentPath,
                        isDirectory: !isLast
                    )

                    // ファイルの場合は変更ステータスを設定
                    if isLast {
                        node.changeStatus = changedPathsStatus[path]
                    }

                    // 親に追加またはルートに追加
                    if let parent = parentNode {
                        parent.children.append(node)
                    } else {
                        rootNodes[component] = node
                    }
                }

                // ディレクトリの場合は子ノードマップを更新
                if !isLast {
                    // 子ノードをマップに変換
                    var childMap: [String: FileTreeNode] = [:]
                    for child in node.children {
                        childMap[child.name] = child
                    }
                    currentNodes = childMap
                    parentNode = node
                }
            }
        }

        // ルートノードを配列に変換してソート
        return sortNodes(Array(rootNodes.values))
    }

    /// ノードをソート（ディレクトリ優先、名前順）
    static func sortNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }.map { node in
            if node.isDirectory && !node.children.isEmpty {
                node.children = sortNodes(node.children)
            }
            return node
        }
    }

    /// ディレクトリが変更されたファイルを含むかどうか
    var hasChangedDescendant: Bool {
        if changeStatus != nil { return true }
        return children.contains { $0.hasChangedDescendant }
    }

    /// ディレクトリの変更ステータス（子の変更を反映）
    var effectiveChangeStatus: ChangeStatus? {
        if changeStatus != nil { return changeStatus }
        if isDirectory && hasChangedDescendant {
            // 子の中で最も優先度が高いステータスを返す
            let childStatuses = children.compactMap { $0.effectiveChangeStatus }
            if childStatuses.contains(.added) { return .added }
            if childStatuses.contains(.deleted) { return .deleted }
            if childStatuses.contains(.modified) { return .modified }
        }
        return nil
    }
}

// MARK: - Changed File

/// 変更されたファイル
struct ChangedFile: Identifiable, Hashable {
    let path: String
    let status: ChangeStatus

    var id: String { path }

    /// ファイル名のみ
    var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// ディレクトリパス
    var directory: String {
        (path as NSString).deletingLastPathComponent
    }
}

/// ファイルの変更ステータス
enum ChangeStatus: String {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"

    var color: Color {
        switch self {
        case .added: return .green
        case .modified: return .yellow
        case .deleted: return .red
        case .renamed: return .blue
        case .copied: return .purple
        }
    }

    var icon: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .copied: return "doc.on.doc.fill"
        }
    }

    var label: String {
        switch self {
        case .added: return "追加"
        case .modified: return "変更"
        case .deleted: return "削除"
        case .renamed: return "名前変更"
        case .copied: return "コピー"
        }
    }
}

// MARK: - Diff Line

/// 差分の1行
struct DiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int?
    let content: String
    let type: DiffLineType
}

/// 差分行のタイプ
enum DiffLineType {
    case context    // 変更なし
    case added      // 追加
    case deleted    // 削除
    case header     // ヘッダー（@@など）
    case meta       // メタ情報

    var color: Color {
        switch self {
        case .context: return .primary
        case .added: return .green
        case .deleted: return .red
        case .header: return .cyan
        case .meta: return .secondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return .green.opacity(0.15)
        case .deleted: return .red.opacity(0.15)
        default: return .clear
        }
    }
}

// MARK: - Diff Parser

/// 差分パーサー
struct DiffParser {
    /// 差分文字列をパースして行の配列に変換
    static func parse(_ diffString: String) -> [DiffLine] {
        let lines = diffString.components(separatedBy: "\n")
        var result: [DiffLine] = []
        var lineNumber = 0

        for line in lines {
            let type: DiffLineType
            let content: String

            if line.hasPrefix("@@") {
                type = .header
                content = line
                // 行番号をリセット
                if let range = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    lineNumber = Int(line[range].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                type = .meta
                content = line
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
                type = .meta
                content = line
            } else if line.hasPrefix("+") {
                type = .added
                content = String(line.dropFirst())
                lineNumber += 1
            } else if line.hasPrefix("-") {
                type = .deleted
                content = String(line.dropFirst())
            } else if line.hasPrefix(" ") {
                type = .context
                content = String(line.dropFirst())
                lineNumber += 1
            } else {
                type = .context
                content = line
                if !line.isEmpty {
                    lineNumber += 1
                }
            }

            result.append(DiffLine(
                lineNumber: type == .context || type == .added ? lineNumber : nil,
                content: content,
                type: type
            ))
        }

        return result
    }
}

// MARK: - Diff Context

/// 差分ビューアのコンテキスト
class DiffContext: ObservableObject {
    let repository: Repository
    let commits: [Commit]  // 1つまたは2つ
    let sourcePath: URL

    @Published var changedFiles: [ChangedFile] = []
    @Published var fileTree: [FileTreeNode] = []
    @Published var selectedFilePath: String?
    @Published var diffLines: [DiffLine] = []
    @Published var fileContent: String = ""
    @Published var isLoading = false
    @Published var isLoadingTree = false
    @Published var showDiff: Bool  // true=差分, false=ファイル全体

    /// 閲覧モードかどうか（差分表示なし）
    let browseMode: Bool

    /// シングルコミットモードかどうか
    var isSingleCommit: Bool {
        commits.count == 1
    }

    /// 表示用タイトル
    var title: String {
        if browseMode {
            return "ファイル閲覧: \(commits[0].shortSHA)"
        }
        if isSingleCommit {
            return commits[0].shortSHA
        } else {
            return "\(commits[0].shortSHA)..\(commits[1].shortSHA)"
        }
    }

    /// 対象のSHA（差分取得用）
    var targetSHA: String {
        isSingleCommit ? commits[0].sha : commits[1].sha
    }

    init(repository: Repository, commits: [Commit], browseMode: Bool = false) {
        self.repository = repository
        self.commits = commits
        self.browseMode = browseMode
        self.showDiff = !browseMode  // 閲覧モードの場合はデフォルトでファイル全体表示
        self.sourcePath = AppSettings.shared.repositorySourceURL(
            owner: repository.owner,
            name: repository.name
        )
    }

    /// ファイルツリーと変更ファイル一覧を読み込む
    @MainActor
    func loadFileTree() async {
        isLoadingTree = true
        defer { isLoadingTree = false }

        do {
            // 変更ファイル一覧を取得
            if isSingleCommit {
                changedFiles = try await GitService.shared.getChangedFiles(
                    sha: commits[0].sha,
                    at: sourcePath
                )
            } else {
                changedFiles = try await GitService.shared.getChangedFilesBetween(
                    from: commits[0].sha,
                    to: commits[1].sha,
                    at: sourcePath
                )
            }

            // 全ファイルパスを取得
            var allPaths = try await GitService.shared.getAllFilePaths(
                sha: targetSHA,
                at: sourcePath
            )

            // 削除されたファイルはls-treeに含まれないため、追加する
            let deletedPaths = changedFiles
                .filter { $0.status == .deleted }
                .map { $0.path }
            allPaths.append(contentsOf: deletedPaths)

            // ツリーを構築
            fileTree = FileTreeNode.buildTree(from: allPaths, changedFiles: changedFiles)

        } catch {
            print("[DiffContext] ファイルツリー取得エラー: \(error)")
        }
    }

    /// ファイルを選択して内容を読み込む
    @MainActor
    func selectFile(path: String) async {
        selectedFilePath = path
        isLoading = true
        defer { isLoading = false }

        // 変更ファイルかどうかチェック
        let changedFile = changedFiles.first { $0.path == path }

        do {
            if let changedFile = changedFile {
                // 変更ファイルの場合: 差分を取得
                let diffString: String
                if isSingleCommit {
                    diffString = try await GitService.shared.getFileDiff(
                        sha: commits[0].sha,
                        filePath: path,
                        at: sourcePath
                    )
                } else {
                    diffString = try await GitService.shared.getFileDiffBetween(
                        from: commits[0].sha,
                        to: commits[1].sha,
                        filePath: path,
                        at: sourcePath
                    )
                }
                diffLines = DiffParser.parse(diffString)

                // 削除ファイルの場合は親コミットから取得
                if changedFile.status == .deleted {
                    // シングルコミットの場合は親SHA、比較の場合はfromSHA
                    let parentSHA = isSingleCommit ? commits[0].parentSHAs.first : commits[0].sha
                    if let sha = parentSHA {
                        fileContent = try await GitService.shared.getFileContent(
                            sha: sha,
                            filePath: path,
                            at: sourcePath
                        )
                    } else {
                        fileContent = "(削除前のファイル内容を取得できません)"
                    }
                } else {
                    fileContent = try await GitService.shared.getFileContent(
                        sha: targetSHA,
                        filePath: path,
                        at: sourcePath
                    )
                }
            } else {
                // 変更なしファイル: ファイル全体のみ取得
                diffLines = []
                fileContent = try await GitService.shared.getFileContent(
                    sha: targetSHA,
                    filePath: path,
                    at: sourcePath
                )
            }
        } catch {
            print("[DiffContext] ファイル読み込みエラー: \(error)")
            diffLines = []
            fileContent = "エラー: \(error.localizedDescription)"
        }
    }

    /// 選択中のファイルの変更ステータス
    var selectedFileChangeStatus: ChangeStatus? {
        guard let path = selectedFilePath else { return nil }
        return changedFiles.first { $0.path == path }?.status
    }
}
