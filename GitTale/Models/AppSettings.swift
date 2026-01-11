//
//  AppSettings.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/11.
//

import Foundation
import SwiftUI

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let workingDirectory = "workingDirectory"
    }

    // MARK: - Working Directory

    /// ベースディレクトリ（~/.GitTale）
    var workingDirectory: String {
        get {
            defaults.string(forKey: Keys.workingDirectory) ?? defaultWorkingDirectory
        }
        set {
            defaults.set(newValue, forKey: Keys.workingDirectory)
        }
    }

    /// デフォルトのWorking Directory（~/.GitTale）
    var defaultWorkingDirectory: String {
        return realHomeDirectory.appendingPathComponent(".GitTale").path
    }

    /// 実際のホームディレクトリを取得（サンドボックス回避）
    /// SandBoxアプリではNSHomeDirectory()が使えないため、getpwuid(getuid())を使用
    private var realHomeDirectory: URL {
        guard let pw = getpwuid(getuid()),
              let homeDir = pw.pointee.pw_dir else {
            // フォールバック（通常はここには来ない）
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: homeDir))
    }

    /// UserDefaultsに保存された値が不正（サンドボックス内等）の場合はリセット
    func resetInvalidPathIfNeeded() {
        if let saved = defaults.string(forKey: Keys.workingDirectory),
           saved.contains("Containers") {
            defaults.removeObject(forKey: Keys.workingDirectory)
        }
    }

    /// Working DirectoryのURLを取得
    var workingDirectoryURL: URL {
        URL(fileURLWithPath: workingDirectory)
    }

    // MARK: - Directory Structure

    /// リポジトリ格納ディレクトリ（~/.GitTale/repositories）
    var repositoriesDirectoryURL: URL {
        workingDirectoryURL.appendingPathComponent("repositories")
    }

    /// キャッシュディレクトリ（~/.GitTale/cache）
    var cacheDirectoryURL: URL {
        workingDirectoryURL.appendingPathComponent("cache")
    }

    /// 特定リポジトリのディレクトリを取得（~/.GitTale/repositories/{owner}/{name}）
    func repositoryDirectoryURL(owner: String, name: String) -> URL {
        repositoriesDirectoryURL
            .appendingPathComponent(owner)
            .appendingPathComponent(name)
    }

    /// 特定リポジトリのメタデータJSONパス
    func repositoryMetadataURL(owner: String, name: String) -> URL {
        repositoryDirectoryURL(owner: owner, name: name)
            .appendingPathComponent("\(name).json")
    }

    /// 特定リポジトリのソースコードディレクトリ
    func repositorySourceURL(owner: String, name: String) -> URL {
        repositoryDirectoryURL(owner: owner, name: name)
            .appendingPathComponent("source")
    }

    // MARK: - Directory Setup

    /// 必要なディレクトリ構造を作成
    func ensureDirectoryStructureExists() throws {
        let fileManager = FileManager.default

        let directories = [
            workingDirectoryURL,
            repositoriesDirectoryURL,
            cacheDirectoryURL
        ]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    /// 特定リポジトリ用のディレクトリを作成
    func ensureRepositoryDirectoryExists(owner: String, name: String) throws {
        let fileManager = FileManager.default
        let repoDir = repositoryDirectoryURL(owner: owner, name: name)
        let sourceDir = repositorySourceURL(owner: owner, name: name)

        if !fileManager.fileExists(atPath: repoDir.path) {
            try fileManager.createDirectory(at: repoDir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: sourceDir.path) {
            try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        }
    }

    private init() {}
}
