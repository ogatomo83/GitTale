# GitTale - UI設計書

## 1. デザイン原則

### 1.1 Human Interface Guidelines準拠

| 原則 | 適用 |
|------|------|
| **Clarity** | 階層構造を明確に。ストーリーが主役 |
| **Deference** | コンテンツファースト。UIは控えめに |
| **Depth** | タイムライン→グループ→コミットへのドリルダウン |

### 1.2 カラーシステム

```swift
extension Color {
    // Change Categories
    static let feature = Color.green
    static let fix = Color.red
    static let refactor = Color.purple
    static let docs = Color.blue
    static let test = Color.yellow
    static let chore = Color.gray

    // Semantic
    static let highImpact = Color.red
    static let mediumImpact = Color.orange
    static let lowImpact = Color.gray
}
```

---

## 2. 画面構成

### 2.1 全体レイアウト

```
┌─────────────────────────────────────────────────────────────────────────┐
│  GitTale                                              [−][□][×]         │
├────────────────┬────────────────────────────────────────────────────────┤
│                │                                                        │
│   Welcome      │                                                        │
│   ──────────   │     Drop a Git repository here                        │
│                │                                                        │
│   Recent:      │              [📁]                                      │
│   ├ react      │                                                        │
│   ├ vue        │     or click to browse                                │
│   └ rust       │                                                        │
│                │                                                        │
│   ──────────   │                                                        │
│   ⚙ Settings   │                                                        │
│                │                                                        │
└────────────────┴────────────────────────────────────────────────────────┘

        ↓ リポジトリ選択後

┌─────────────────────────────────────────────────────────────────────────┐
│  GitTale                                              [−][□][×]         │
├────────────────┬──────────────────────────────┬─────────────────────────┤
│                │                              │                         │
│   react        │  Timeline                    │  Detail                 │
│   ──────────   │  ────────                    │  ──────                 │
│                │                              │                         │
│   📊 Timeline  │  [Day][Week][Month][Version] │  Commit abc1234         │
│   📖 Story     │                              │                         │
│                │  ┌─ v18.3.0 ───────────────┐ │  feat: Add hooks        │
│   ──────────   │  │                         │ │                         │
│                │  │  "Concurrent Features"  │ │  ┌─────────────────┐   │
│   ⚙ Settings   │  │                         │ │  │ AI Summary      │   │
│                │  │  [展開]                  │ │  │                 │   │
│                │  └─────────────────────────┘ │  │ This commit...  │   │
│                │                              │  └─────────────────┘   │
│                │  ┌─ 2024-W03 ─────────────┐  │                         │
│                │  │  ● [feat] Add API      │  │  Files: 4              │
│                │  │  ● [fix] Fix crash     │  │  +142 -38              │
│                │  └─────────────────────────┘ │                         │
│                │                              │                         │
└────────────────┴──────────────────────────────┴─────────────────────────┘
```

### 2.2 NavigationSplitView

```swift
struct ContentView: View {
    @State private var selectedView: SidebarItem = .timeline
    @State private var selectedEntry: TimelineEntry?
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedView: $selectedView,
                viewModel: viewModel
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } content: {
            ContentColumnView(
                selectedView: selectedView,
                selectedEntry: $selectedEntry,
                viewModel: viewModel
            )
            .navigationSplitViewColumnWidth(min: 400, ideal: 500)
        } detail: {
            DetailColumnView(
                selectedEntry: selectedEntry,
                viewModel: viewModel
            )
        }
    }
}

enum SidebarItem: Hashable {
    case timeline
    case story
    case settings
}
```

---

## 3. サイドバー

### 3.1 SidebarView

```swift
struct SidebarView: View {
    @Binding var selectedView: SidebarItem
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: $selectedView) {
            // Repository Header
            if let repo = viewModel.currentRepository {
                RepositoryHeader(name: repo.name)
            }

            Section {
                Label("Timeline", systemImage: "clock")
                    .tag(SidebarItem.timeline)

                Label("Project Story", systemImage: "book")
                    .tag(SidebarItem.story)
            }

            Section("Recent") {
                ForEach(viewModel.recentRepositories, id: \.self) { path in
                    RecentRepositoryRow(path: path) {
                        viewModel.openRepository(at: URL(fileURLWithPath: path))
                    }
                }
            }

            Section {
                Label("Settings", systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("GitTale")
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.showRepositoryPicker()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
    }
}

struct RepositoryHeader: View {
    let name: String

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            Text(name)
                .font(.headline)
        }
        .padding(.vertical, 4)
    }
}
```

---

## 4. タイムラインビュー

### 4.1 TimelineView

```swift
struct TimelineView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedEntry: TimelineEntry?
    @State private var zoomLevel: ZoomLevel = .week
    @State private var searchText = ""

    enum ZoomLevel: String, CaseIterable {
        case day, week, month, version

        var displayName: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TimelineToolbar(
                zoomLevel: $zoomLevel,
                searchText: $searchText,
                onRefresh: viewModel.refresh
            )

            Divider()

            // Content
            if viewModel.isLoading {
                LoadingView(message: "Loading commits...")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.groupedEntries(for: zoomLevel)) { group in
                            GroupSection(
                                group: group,
                                selectedEntry: $selectedEntry
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search commits")
        .navigationTitle(viewModel.currentRepository?.name ?? "")
        .navigationSubtitle("\(viewModel.commitCount) commits")
    }
}

struct TimelineToolbar: View {
    @Binding var zoomLevel: TimelineView.ZoomLevel
    @Binding var searchText: String
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Picker("Zoom", selection: $zoomLevel) {
                ForEach(TimelineView.ZoomLevel.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding()
    }
}
```

### 4.2 GroupSection

```swift
struct GroupSection: View {
    let group: GroupEntry
    @Binding var selectedEntry: TimelineEntry?
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group Header
            GroupHeader(
                group: group,
                isExpanded: $isExpanded
            )

            if isExpanded {
                // Group Summary (if available)
                if let summary = group.summary {
                    GroupNarrativeCard(summary: summary)
                }

                // Commits
                ForEach(group.entries.prefix(10)) { entry in
                    CommitRow(entry: entry, isSelected: selectedEntry?.id == entry.id)
                        .onTapGesture {
                            selectedEntry = entry
                        }
                }

                // Show more button
                if group.entries.count > 10 {
                    Button {
                        // Show all commits
                    } label: {
                        Text("+ \(group.entries.count - 10) more commits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GroupHeader: View {
    let group: GroupEntry
    @Binding var isExpanded: Bool

    var body: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            if let tag = group.group.tag {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.orange)
            }

            Text(group.group.name)
                .font(.headline)

            Spacer()

            Text("\(group.entries.count) commits")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### 4.3 CommitRow

```swift
struct CommitRow: View {
    let entry: TimelineEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Category Icon
            CategoryIcon(category: entry.displayCategory)

            VStack(alignment: .leading, spacing: 4) {
                // Summary or Subject
                if let summary = entry.summary {
                    Text(summary.summary)
                        .font(.body)
                } else {
                    Text(entry.commit.subject)
                        .font(.body.monospaced())
                }

                // Metadata
                HStack(spacing: 8) {
                    Text(entry.commit.shortSHA)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    Text(entry.commit.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(entry.commit.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Impact badge
            if let impact = entry.summary?.impact, impact == .high {
                ImpactBadge(impact: impact)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CategoryIcon: View {
    let category: ChangeCategory

    var body: some View {
        Image(systemName: category.icon)
            .foregroundStyle(Color(category.color))
            .frame(width: 20)
    }
}

struct ImpactBadge: View {
    let impact: Impact

    var body: some View {
        Text(impact.displayName.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.highImpact.opacity(0.2))
            .foregroundStyle(.red)
            .clipShape(Capsule())
    }
}
```

---

## 5. 詳細ビュー

### 5.1 DetailView

```swift
struct DetailColumnView: View {
    let selectedEntry: TimelineEntry?
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let entry = selectedEntry {
                CommitDetailView(entry: entry, viewModel: viewModel)
            } else {
                EmptyDetailView()
            }
        }
    }
}

struct CommitDetailView: View {
    let entry: TimelineEntry
    @ObservedObject var viewModel: AppViewModel
    @State private var isGeneratingSummary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                CommitHeader(entry: entry)

                Divider()

                // AI Summary
                AISummarySection(
                    entry: entry,
                    isGenerating: isGeneratingSummary,
                    onGenerate: generateSummary
                )

                Divider()

                // Commit Message
                CommitMessageSection(commit: entry.commit)

                Divider()

                // Diff Stats
                DiffStatsSection(diff: entry.diff)

                Divider()

                // Keywords
                if let keywords = entry.summary?.keywords, !keywords.isEmpty {
                    KeywordsSection(keywords: keywords)
                }
            }
            .padding()
        }
        .navigationTitle("Commit Detail")
    }

    private func generateSummary() {
        isGeneratingSummary = true
        Task {
            await viewModel.generateSummary(for: entry)
            isGeneratingSummary = false
        }
    }
}

struct CommitHeader: View {
    let entry: TimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.commit.subject)
                .font(.title2.bold())

            HStack {
                CategoryBadge(category: entry.displayCategory)

                if let impact = entry.summary?.impact {
                    ImpactBadge(impact: impact)
                }
            }
        }
    }
}

struct AISummarySection: View {
    let entry: TimelineEntry
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Summary")
                    .font(.headline)

                Spacer()

                if entry.summary == nil {
                    Button("Generate", action: onGenerate)
                        .disabled(isGenerating)
                }
            }

            if isGenerating {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let summary = entry.summary {
                Text(summary.summary)
                    .font(.body)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No summary available. Click 'Generate' to create one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

struct DiffStatsSection: View {
    let diff: DiffStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changes")
                .font(.headline)

            HStack(spacing: 16) {
                Label("+\(diff.additions)", systemImage: "plus")
                    .foregroundStyle(.green)

                Label("-\(diff.deletions)", systemImage: "minus")
                    .foregroundStyle(.red)

                Label("\(diff.fileCount) files", systemImage: "doc")
                    .foregroundStyle(.secondary)
            }

            // File list
            ForEach(diff.filesChanged, id: \.path) { file in
                FileChangeRow(file: file)
            }
        }
    }
}

struct FileChangeRow: View {
    let file: FileChange

    var body: some View {
        HStack {
            statusIcon

            Text(file.path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch file.status {
        case .added:
            Text("A")
                .foregroundStyle(.green)
        case .modified:
            Text("M")
                .foregroundStyle(.orange)
        case .deleted:
            Text("D")
                .foregroundStyle(.red)
        case .renamed:
            Text("R")
                .foregroundStyle(.blue)
        }
    }
}
```

---

## 6. プロジェクトストーリービュー

```swift
struct ProjectStoryView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isGenerating = false

    var body: some View {
        ScrollView {
            if let story = viewModel.projectStory {
                StoryContent(story: story)
            } else {
                EmptyStoryView(
                    isGenerating: isGenerating,
                    onGenerate: generateStory
                )
            }
        }
        .navigationTitle("Project Story")
    }

    private func generateStory() {
        isGenerating = true
        Task {
            await viewModel.generateProjectStory()
            isGenerating = false
        }
    }
}

struct StoryContent: View {
    let story: ProjectStory

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Tagline
            Text(story.tagline)
                .font(.title)
                .italic()

            Divider()

            // Origin
            StorySection(title: "Origin", content: story.origin)

            // Evolution
            StorySection(title: "Evolution", content: story.evolution)

            // Philosophy
            StorySection(title: "Philosophy", content: story.philosophy)

            // Challenges
            StorySection(title: "Challenges Overcome", content: story.challenges)

            // Milestones
            if !story.milestones.isEmpty {
                MilestonesSection(milestones: story.milestones)
            }
        }
        .padding()
    }
}

struct StorySection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(content)
                .font(.body)
        }
    }
}

struct MilestonesSection: View {
    let milestones: [Milestone]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Milestones")
                .font(.headline)

            ForEach(milestones, id: \.version) { milestone in
                HStack(alignment: .top) {
                    Text(milestone.version)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(milestone.significance)
                        .font(.body)
                }
            }
        }
    }
}
```

---

## 7. 設定ビュー

```swift
struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var apiKeyInput = ""
    @State private var connectionStatus: ConnectionStatus = .unknown

    var body: some View {
        Form {
            // AI Provider Section
            Section("AI Provider") {
                Picker("Provider", selection: $settings.selectedProvider) {
                    ForEach(AIProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                switch settings.selectedProvider {
                case .openai:
                    OpenAISettings(connectionStatus: $connectionStatus)
                case .anthropic:
                    AnthropicSettings(connectionStatus: $connectionStatus)
                case .ollama:
                    OllamaSettings(connectionStatus: $connectionStatus)
                }
            }

            // Output Section
            Section("Output") {
                Picker("Language", selection: $settings.outputLanguage) {
                    ForEach(OutputLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            // Cache Section
            Section("Cache") {
                HStack {
                    Text("Cache Location")
                    Spacer()
                    Text(".gittale/cache/")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospaced())
                }

                Button("Clear All Caches", role: .destructive) {
                    // Clear caches
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

struct OllamaSettings: View {
    @StateObject private var settings = AppSettings.shared
    @Binding var connectionStatus: ConnectionStatus

    var body: some View {
        HStack {
            TextField("Host", text: $settings.ollamaHost)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            Text(":")

            TextField("Port", value: $settings.ollamaPort, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }

        TextField("Model", text: $settings.ollamaModel)
            .textFieldStyle(.roundedBorder)

        HStack {
            ConnectionStatusView(status: connectionStatus)

            Button("Test Connection") {
                testConnection()
            }
        }
    }

    private func testConnection() {
        connectionStatus = .checking
        Task {
            let provider = OllamaProvider(
                host: settings.ollamaHost,
                port: settings.ollamaPort,
                model: settings.ollamaModel
            )
            let available = await provider.isAvailable()
            connectionStatus = available ? .connected : .disconnected
        }
    }
}

enum ConnectionStatus {
    case unknown, checking, connected, disconnected
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .unknown:
                Circle().fill(.gray).frame(width: 8, height: 8)
                Text("Not tested")
            case .checking:
                ProgressView().scaleEffect(0.5)
                Text("Checking...")
            case .connected:
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Connected")
            case .disconnected:
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Not available")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
```

---

## 8. ウェルカムビュー（初回起動時）

```swift
struct WelcomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Drop a Git Repository")
                .font(.title2)

            Text("or")
                .foregroundStyle(.secondary)

            Button("Browse...") {
                viewModel.showRepositoryPicker()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                viewModel.openRepository(at: url)
            }
        }

        return true
    }
}
```

---

## 9. 共通コンポーネント

```swift
// MARK: - Badges

struct CategoryBadge: View {
    let category: ChangeCategory

    var body: some View {
        Label(category.displayName, systemImage: category.icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(category.color).opacity(0.2))
            .foregroundStyle(Color(category.color))
            .clipShape(Capsule())
    }
}

// MARK: - Loading

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty States

struct EmptyDetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Commit",
            systemImage: "arrow.left.circle",
            description: Text("Choose a commit from the timeline to see details")
        )
    }
}

struct EmptyStoryView: View {
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Story Yet", systemImage: "book.closed")
        } description: {
            Text("Generate a project story from your commit history")
        } actions: {
            Button("Generate Story", action: onGenerate)
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keywords

struct KeywordsSection: View {
    let keywords: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keywords")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
```
