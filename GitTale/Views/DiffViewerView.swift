//
//  DiffViewerView.swift
//  GitTale
//
//  Created by ogatomo83 on 2026/01/12.
//

import SwiftUI
import AppKit

// MARK: - Diff Viewer View

struct DiffViewerView: View {
    @StateObject var context: DiffContext

    var body: some View {
        HStack(spacing: 0) {
            // 左: ファイルツリー（固定幅）
            FileTreeSidebarView(context: context)
                .frame(width: 280)

            Divider()

            // 右: エディタビュー（残り全体）
            EditorAreaView(context: context)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("差分: \(context.title)")
        .task {
            await context.loadFileTree()
        }
    }
}

// MARK: - File Tree Sidebar View

struct FileTreeSidebarView: View {
    @ObservedObject var context: DiffContext

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー: エクスプローラー
            HStack {
                Text("エクスプローラー")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorColors.lineNumber)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EditorColors.sidebar)

            // リポジトリ名ヘッダー
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(EditorColors.lineNumber)
                Text(context.repository.name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorColors.text)
                Spacer()
                // 変更ファイル数バッジ
                if !context.changedFiles.isEmpty {
                    Text("\(context.changedFiles.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(EditorColors.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.3))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(EditorColors.sidebar.opacity(0.8))

            // ファイルツリー
            if context.isLoadingTree {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(EditorColors.text)
                    Text("ファイルツリーを読み込み中...")
                        .font(.caption)
                        .foregroundStyle(EditorColors.lineNumber)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EditorColors.sidebar)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(context.fileTree) { node in
                            FileTreeNodeView(
                                node: node,
                                selectedPath: context.selectedFilePath,
                                depth: 0
                            ) { path in
                                Task {
                                    await context.selectFile(path: path)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(EditorColors.sidebar)
            }
        }
        .background(EditorColors.sidebar)
    }
}

// MARK: - File Tree Node View

struct FileTreeNodeView: View {
    @ObservedObject var node: FileTreeNode
    let selectedPath: String?
    let depth: Int
    let onSelect: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ノード行
            HStack(spacing: 4) {
                // インデント
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 16)
                }

                // 展開アイコン（ディレクトリのみ）
                if node.isDirectory {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(EditorColors.lineNumber)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                // ファイル/フォルダアイコン
                Image(systemName: node.isDirectory ? (node.isExpanded ? "folder.fill" : "folder") : fileIcon(for: node.name))
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                // ファイル名
                Text(node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                Spacer()

                // 変更ステータスインジケーター
                if let status = node.changeStatus {
                    Text(statusLetter(for: status))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(status.color)
                        .frame(width: 16)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                } else {
                    onSelect(node.path)
                }
            }

            // 子ノード（展開時）
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        selectedPath: selectedPath,
                        depth: depth + 1,
                        onSelect: onSelect
                    )
                }
            }
        }
    }

    /// 行の背景色
    private var rowBackground: Color {
        if selectedPath == node.path && !node.isDirectory {
            return EditorColors.selectedLine
        }
        if isHovered {
            return EditorColors.hoverLine
        }
        return .clear
    }

    /// アイコンの色
    private var iconColor: Color {
        if node.isDirectory {
            return node.hasChangedDescendant ? Color.yellow : Color(red: 0.557, green: 0.757, blue: 0.906)  // VSCode folder blue
        }
        if let status = node.changeStatus {
            return status.color
        }
        return EditorColors.text.opacity(0.7)
    }

    /// テキストの色
    private var textColor: Color {
        if let status = node.changeStatus {
            return status.color
        }
        return EditorColors.text
    }

    /// ファイル拡張子に応じたアイコン
    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond.fill"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "rs": return "gearshape.fill"
        case "java", "kt": return "cup.and.saucer.fill"
        case "c", "cpp", "h", "hpp": return "c.square.fill"
        case "cs": return "number.square.fill"
        case "html", "htm": return "globe"
        case "css", "scss", "sass": return "paintpalette.fill"
        case "json": return "curlybraces.square.fill"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "yml", "yaml": return "list.bullet.rectangle"
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        case "sh", "bash", "zsh": return "terminal.fill"
        case "sql": return "cylinder.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "ico": return "photo"
        case "pdf": return "doc.fill"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "gitignore", "gitattributes": return "arrow.triangle.branch"
        case "dockerfile": return "shippingbox.fill"
        case "lock": return "lock.fill"
        default: return "doc"
        }
    }

    /// ステータス文字
    private func statusLetter(for status: ChangeStatus) -> String {
        switch status {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        }
    }
}

// MARK: - Editor Area View

struct EditorAreaView: View {
    @ObservedObject var context: DiffContext

    var body: some View {
        VStack(spacing: 0) {
            // タブバー
            EditorTabBarView(context: context)

            // コンテンツ
            if context.selectedFilePath == nil {
                // ファイル未選択
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(EditorColors.lineNumber)
                    Text("ファイルを選択してください")
                        .font(.headline)
                        .foregroundStyle(EditorColors.text)
                    Text("左のファイルツリーからファイルを選択すると内容が表示されます")
                        .font(.subheadline)
                        .foregroundStyle(EditorColors.lineNumber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EditorColors.background)
            } else if context.isLoading {
                // 読み込み中
                VStack {
                    ProgressView()
                        .tint(EditorColors.text)
                    Text("読み込み中...")
                        .font(.caption)
                        .foregroundStyle(EditorColors.lineNumber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EditorColors.background)
            } else if !context.browseMode && context.showDiff && !context.diffLines.isEmpty {
                // 差分表示（閲覧モードでは表示しない）
                DiffLinesView(lines: context.diffLines)
            } else {
                // ファイル全体表示
                FileContentView(content: context.fileContent)
            }
        }
        .background(EditorColors.background)
    }
}

// MARK: - Editor Tab Bar View

struct EditorTabBarView: View {
    @ObservedObject var context: DiffContext

    var body: some View {
        HStack(spacing: 0) {
            // ファイルタブ
            if let path = context.selectedFilePath {
                HStack(spacing: 8) {
                    // ファイルアイコン
                    Image(systemName: fileIcon(for: (path as NSString).lastPathComponent))
                        .font(.system(size: 14))
                        .foregroundStyle(EditorColors.text.opacity(0.7))

                    // ファイル名
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundStyle(EditorColors.text)
                        .lineLimit(1)

                    // 変更ステータス
                    if let status = context.selectedFileChangeStatus {
                        Text(statusLetter(for: status))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(status.color)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(EditorColors.background)
                .overlay(
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2),
                    alignment: .bottom
                )
            }

            Spacer()

            // 表示切り替え（変更ファイルのみ、閲覧モードでは非表示）
            if !context.browseMode && context.selectedFileChangeStatus != nil {
                HStack(spacing: 4) {
                    TabButton(title: "差分", isSelected: context.showDiff) {
                        context.showDiff = true
                    }
                    TabButton(title: "全体", isSelected: !context.showDiff) {
                        context.showDiff = false
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .frame(height: 36)
        .background(EditorColors.tabBar)
    }

    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "rb": return "diamond.fill"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintpalette.fill"
        case "json": return "curlybraces.square.fill"
        case "md": return "doc.text"
        case "yml", "yaml": return "list.bullet.rectangle"
        default: return "doc"
        }
    }

    private func statusLetter(for status: ChangeStatus) -> String {
        switch status {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? EditorColors.text : EditorColors.lineNumber)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isSelected ? EditorColors.background : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diff Lines View (Selectable)

struct DiffLinesView: View {
    let lines: [DiffLine]

    var body: some View {
        HStack(spacing: 0) {
            // 左側: 行番号・差分記号ガター（SwiftUI）
            DiffGutterView(lines: lines)

            // 右側: コード内容（NSTextView - 選択可能）
            SelectableDiffContentView(lines: lines)
        }
        .background(EditorColors.background)
    }
}

// MARK: - Diff Gutter View

struct DiffGutterView: View {
    let lines: [DiffLine]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        // 行番号
                        Text(line.lineNumber.map { String($0) } ?? "")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(EditorColors.lineNumber)

                        // 差分記号
                        Text(diffSymbol(for: line.type))
                            .frame(width: 20, alignment: .center)
                            .foregroundStyle(diffSymbolColor(for: line.type))
                    }
                    .frame(height: 20)
                    .background(gutterBackground(for: line.type))
                }
            }
            .padding(.trailing, 4)
        }
        .frame(width: 68)
        .background(EditorColors.gutter)
        .disabled(true)  // スクロール連動のみ
    }

    private func diffSymbol(for type: DiffLineType) -> String {
        switch type {
        case .added: return "+"
        case .deleted: return "−"
        default: return ""
        }
    }

    private func diffSymbolColor(for type: DiffLineType) -> Color {
        switch type {
        case .added: return EditorColors.addedText
        case .deleted: return EditorColors.deletedText
        default: return .clear
        }
    }

    private func gutterBackground(for type: DiffLineType) -> Color {
        switch type {
        case .added: return EditorColors.addedGutter
        case .deleted: return EditorColors.deletedGutter
        default: return .clear
        }
    }
}

// MARK: - Selectable Diff Content View (NSTextView wrapper)

struct SelectableDiffContentView: NSViewRepresentable {
    let lines: [DiffLine]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = DiffTextView()

        // テキストビュー設定
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(EditorColors.background)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // スクロールビュー設定
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.backgroundColor = NSColor(EditorColors.background)

        // 横スクロール対応
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DiffTextView else { return }
        textView.updateContent(lines: lines)
    }
}

// MARK: - Diff Text View (Custom NSTextView with line backgrounds)

class DiffTextView: NSTextView {
    private var lineBackgrounds: [(range: NSRange, color: NSColor)] = []

    func updateContent(lines: [DiffLine]) {
        // Attributed stringを構築
        let attributedString = NSMutableAttributedString()
        lineBackgrounds = []

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 20
        paragraphStyle.maximumLineHeight = 20

        var currentLocation = 0

        for (index, line) in lines.enumerated() {
            let content = line.content + (index < lines.count - 1 ? "\n" : "")
            let textColor = textColor(for: line.type)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]

            attributedString.append(NSAttributedString(string: content, attributes: attributes))

            // 背景色の範囲を記録
            let bgColor = backgroundColor(for: line.type)
            if bgColor != NSColor.clear {
                let range = NSRange(location: currentLocation, length: content.count)
                lineBackgrounds.append((range: range, color: bgColor))
            }

            currentLocation += content.count
        }

        // 変更があった場合のみ更新
        if textStorage?.string != attributedString.string {
            textStorage?.setAttributedString(attributedString)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 背景を描画
        NSColor(EditorColors.background).setFill()
        dirtyRect.fill()

        // 行ごとの背景色を描画
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            super.draw(dirtyRect)
            return
        }

        for (range, color) in lineBackgrounds {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.x = 0
            lineRect.size.width = bounds.width
            lineRect.origin.y += textContainerInset.height

            if lineRect.intersects(dirtyRect) {
                color.setFill()
                lineRect.fill()
            }
        }

        super.draw(dirtyRect)
    }

    private func textColor(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: return NSColor(EditorColors.addedText)
        case .deleted: return NSColor(EditorColors.deletedText)
        case .header: return NSColor.cyan
        case .meta: return NSColor(EditorColors.lineNumber)
        case .context: return NSColor(EditorColors.text)
        }
    }

    private func backgroundColor(for type: DiffLineType) -> NSColor {
        switch type {
        case .added: return NSColor(EditorColors.addedLine)
        case .deleted: return NSColor(EditorColors.deletedLine)
        default: return NSColor.clear
        }
    }
}

// MARK: - File Content View

struct FileContentView: View {
    let content: String

    var body: some View {
        HStack(spacing: 0) {
            // 行番号ガター
            LineNumberGutter(content: content)

            // コード内容（選択可能）
            SelectableCodeView(content: content)
        }
        .background(EditorColors.background)
    }
}

// MARK: - Line Number Gutter

struct LineNumberGutter: View {
    let content: String

    private var lineCount: Int {
        content.components(separatedBy: "\n").count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...max(lineCount, 1), id: \.self) { lineNumber in
                    Text("\(lineNumber)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(EditorColors.lineNumber)
                        .frame(height: 20)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 56)
        .background(EditorColors.gutter)
        .disabled(true)  // ガターはスクロール連動のみ
    }
}

// MARK: - Selectable Code View (NSTextView wrapper)

struct SelectableCodeView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // テキストビュー設定
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(EditorColors.background)
        textView.textColor = NSColor(EditorColors.text)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // 行の高さ設定
        textView.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 0
            style.minimumLineHeight = 20
            style.maximumLineHeight = 20
            return style
        }()

        // スクロールビュー設定
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.backgroundColor = NSColor(EditorColors.background)

        // 横スクロール対応
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != content {
            textView.string = content
        }
    }
}

// MARK: - Editor Colors (VSCode Dark+ Theme)

struct EditorColors {
    // 背景色
    static let background = Color(red: 0.118, green: 0.118, blue: 0.118)  // #1e1e1e
    static let gutter = Color(red: 0.118, green: 0.118, blue: 0.118)  // #1e1e1e
    static let tabBar = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626
    static let sidebar = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626

    // テキスト色
    static let text = Color(red: 0.847, green: 0.847, blue: 0.847)  // #d4d4d4
    static let lineNumber = Color(red: 0.522, green: 0.522, blue: 0.522)  // #858585
    static let lineNumberHover = Color(red: 0.769, green: 0.769, blue: 0.769)  // #c4c4c4

    // ホバー・選択
    static let hoverLine = Color(red: 0.173, green: 0.173, blue: 0.173)  // #2c2c2c
    static let selectedLine = Color(red: 0.039, green: 0.227, blue: 0.424)  // #0a3a6c

    // 差分色（追加）
    static let addedLine = Color(red: 0.157, green: 0.235, blue: 0.173)  // #283b2c
    static let addedGutter = Color(red: 0.118, green: 0.314, blue: 0.196)  // #1e5032
    static let addedText = Color(red: 0.522, green: 0.863, blue: 0.522)  // #85dc85

    // 差分色（削除）
    static let deletedLine = Color(red: 0.275, green: 0.157, blue: 0.157)  // #462828
    static let deletedGutter = Color(red: 0.392, green: 0.157, blue: 0.157)  // #642828
    static let deletedText = Color(red: 0.949, green: 0.522, blue: 0.522)  // #f28585
}

#Preview {
    DiffViewerView(
        context: DiffContext(
            repository: Repository(
                owner: "rails",
                name: "rails",
                url: "https://github.com/rails/rails.git"
            ),
            commits: [
                Commit(
                    sha: "abc123",
                    shortSHA: "abc123",
                    author: "Test",
                    email: "test@test.com",
                    date: Date(),
                    message: "Test commit",
                    parentSHAs: []
                )
            ]
        )
    )
}
