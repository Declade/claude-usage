# Architecture Research

**Domain:** Native macOS SwiftUI menu bar utility (token usage tracker)
**Researched:** 2026-03-11
**Confidence:** HIGH — patterns verified against official Apple docs, multiple authoritative SwiftUI/macOS sources, and real-world implementations

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          App Layer                                   │
│  @main ClaudeUsageApp: App                                          │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  MenuBarExtra("Claude Usage", systemImage: "chart.bar")        │ │
│  │    .menuBarExtraStyle(.window)                                 │ │
│  │    MenuBarView  ← @State appModel: AppModel                    │ │
│  └────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  Settings { SettingsView }   (optional, for launch-at-login)   │ │
│  └────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ owns / observes
┌───────────────────────────────▼─────────────────────────────────────┐
│                        State Layer                                   │
│  @Observable AppModel                                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  windowStats:    │  │  weeklyStats:    │  │  lastRefresh:    │  │
│  │  WindowUsage     │  │  WindowUsage     │  │  Date            │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│       ↑ writes                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  UsageService   (refresh(), startPolling(), stopPolling())    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ calls
┌───────────────────────────────▼─────────────────────────────────────┐
│                       Data Layer                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  LogFileScanner                                              │   │
│  │  FileManager.enumerator → discovers **/*.jsonl files         │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
│                             │ raw [UsageEntry]
│  ┌──────────────────────────▼───────────────────────────────────┐   │
│  │  JSONLParser                                                 │   │
│  │  line-by-line JSONDecoder → [UsageEntry]                     │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
│                             │ [UsageEntry]
│  ┌──────────────────────────▼───────────────────────────────────┐   │
│  │  UsageAggregator                                             │   │
│  │  filter by time window → sum token counts → WindowUsage      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                │ reads from
┌───────────────────────────────▼─────────────────────────────────────┐
│                      File System                                     │
│   ~/.claude/projects/**/*.jsonl                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `ClaudeUsageApp` | App entry point; declares `MenuBarExtra` scene + optional `Settings` scene | Owns `AppModel` via `@State` |
| `MenuBarView` | Root dropdown view: two progress bars, token counts, reset timers, quit button | Reads `AppModel` |
| `WindowUsageView` | Reusable sub-view for a single time window (progress bar + stats row) | Receives `WindowUsage` value |
| `AppModel` | Central `@Observable` state holder; orchestrates refresh cycle | Calls `UsageService` |
| `UsageService` | Owns `Timer`; triggers scan+aggregate; pushes results into `AppModel` on `@MainActor` | Calls `LogFileScanner`, `UsageAggregator` |
| `LogFileScanner` | Walks `~/.claude/projects/` with `FileManager.enumerator`; returns all `.jsonl` URLs | Calls `JSONLParser` per file |
| `JSONLParser` | Reads a file as `String`, splits on `\n`, decodes each line via `JSONDecoder` into `UsageEntry` | Pure function / value type |
| `UsageAggregator` | Accepts `[UsageEntry]` + current date; computes sums for the two time windows | Returns `WindowUsage` structs |
| `SettingsView` | Toggle for launch-at-login via `SMAppService`; uses `Toggle` + `onChange` pattern | Reads/writes `SMAppService.mainApp` |

## Recommended Project Structure

```
ClaudeUsage/
├── App/
│   ├── ClaudeUsageApp.swift        # @main, MenuBarExtra scene, Settings scene
│   └── AppModel.swift              # @Observable central state
│
├── Services/
│   ├── UsageService.swift          # Timer loop, coordinates scan → aggregate → publish
│   ├── LogFileScanner.swift        # FileManager traversal, returns [URL]
│   ├── JSONLParser.swift           # Line-by-line decode, returns [UsageEntry]
│   └── UsageAggregator.swift       # Time-window filtering and token summation
│
├── Models/
│   ├── UsageEntry.swift            # Decodable struct: input_tokens, output_tokens, cache_*, timestamp
│   ├── WindowUsage.swift           # Value type: tokensUsed, tokensRemaining, windowEnd, limit
│   └── TimeWindow.swift            # Enum: fourHour, weekly — carries duration and limit constants
│
├── Views/
│   ├── MenuBarView.swift           # Root popover: two WindowUsageView instances + toolbar
│   ├── WindowUsageView.swift       # Reusable progress bar + stats for one window
│   └── SettingsView.swift          # Launch at login toggle
│
└── Resources/
    └── Info.plist                  # LSUIElement = true (hide Dock icon)
```

### Structure Rationale

- **App/**: Separates the entry point and shared state from business logic; `AppModel` is the single source of truth.
- **Services/**: Each file has one job; `UsageService` is the only component that holds a `Timer`; parsing and aggregation are stateless functions that are easy to unit-test.
- **Models/**: Pure value types (`struct`) with no UI dependencies; safe to use on any queue before being handed to `@MainActor`.
- **Views/**: Flat structure — the UI is shallow; avoid nesting unless it grows significantly.

## Architectural Patterns

### Pattern 1: @Observable AppModel as Single Source of Truth

**What:** A single `@Observable` class holds all computed state (`windowStats`, `weeklyStats`, `lastRefresh`). SwiftUI views read from it directly with no extra property wrappers.

**When to use:** macOS 14+ target (which is appropriate here — `MenuBarExtra` requires macOS 13+, and `@Observable` requires macOS 14). Replaces `ObservableObject` + `@Published`.

**Trade-offs:** Simpler syntax, more granular re-rendering (only views reading a changed property re-render). Requires macOS 14 minimum. Cannot be used with `@StateObject` — use `@State` at the scene level.

**Example:**
```swift
@Observable
final class AppModel {
    var windowStats: WindowUsage = .empty
    var weeklyStats: WindowUsage = .empty
    var lastRefresh: Date = .now
}

// App entry point — @State owns the model lifetime
@main
struct ClaudeUsageApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("Claude Usage", systemImage: "chart.bar.fill") {
            MenuBarView()
                .environment(appModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Pattern 2: UsageService with Timer on Background Queue, @MainActor Publish

**What:** `UsageService` fires a repeating `Timer` (or `Task` with `Task.sleep`) on a background queue to scan files and aggregate. Results are published back to `AppModel` via `await MainActor.run { }` to keep UI updates on the main thread.

**When to use:** Any time data loading is I/O-bound. JSONL parsing is fast for Claude Code's log volumes (thousands of entries), but blocking the main thread is still wrong.

**Trade-offs:** Adds one level of async indirection. Simpler than FSEvents for this use case — polling every 30–60 seconds is adequate since token windows reset on a 4-hour cadence. FSEvents would be over-engineering for this data access pattern.

**Example:**
```swift
func startPolling(interval: TimeInterval = 30) {
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let entries = self.scanner.scan()
            let window = self.aggregator.compute(entries: entries, for: .fourHour)
            let weekly = self.aggregator.compute(entries: entries, for: .weekly)
            await MainActor.run {
                self.appModel.windowStats = window
                self.appModel.weeklyStats = weekly
                self.appModel.lastRefresh = .now
            }
        }
    }
}
```

### Pattern 3: Stateless JSONLParser with keyDecodingStrategy

**What:** `JSONLParser` is a pure function (or static methods on a struct) that reads a file URL, splits on `\n`, and decodes each line individually. The `UsageEntry` struct uses `Decodable` with `keyDecodingStrategy = .convertFromSnakeCase` to map `input_tokens` → `inputTokens` automatically.

**When to use:** Always — JSONL is inherently line-oriented; this approach is streaming-friendly and avoids loading the entire file as a JSON array.

**Trade-offs:** Lines that fail to decode (e.g. metadata entries, empty lines) are silently skipped with `try?` — intentional for log files that may contain non-usage entries.

**Example:**
```swift
struct UsageEntry: Decodable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

struct JSONLParser {
    static func parse(url: URL) -> [UsageEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(UsageEntry.self, from: Data($0.utf8)) }
    }
}
```

### Pattern 4: MenuBarExtra with .window Style

**What:** Use `.menuBarExtraStyle(.window)` rather than the default `.menu` style. Window style renders content in a popover-like floating panel, enabling arbitrary SwiftUI layout (ProgressView, custom rows). The default menu style only supports `Button` and `Menu` items.

**When to use:** Any time the dropdown needs progress bars, labels, or layout beyond a plain list of buttons.

**Trade-offs:** The window style has a known gap: no built-in way for content inside the window to dismiss it programmatically. Workaround: use `@Environment(\.openURL)` trick or the `MenuBarExtraAccess` package. For this app, the window dismisses naturally on click-outside, so this is a minor concern.

## Data Flow

### Primary Flow: File System to Menu Bar Display

```
Timer fires (every 30s)
    ↓
UsageService.refresh() [background queue]
    ↓
LogFileScanner.scan()
    → FileManager.enumerator(at: ~/.claude/projects/)
    → filter URLs where hasSuffix(".jsonl")
    → returns [URL]
    ↓
JSONLParser.parse(url:) called per file [background queue]
    → String(contentsOf: url)
    → split("\n") → JSONDecoder per line
    → returns [UsageEntry] (decode failures silently skipped)
    ↓
[UsageEntry] merged across all files
    ↓
UsageAggregator.compute(entries:for:) [background queue]
    → filter entries where timestamp >= windowStart
    → sum(inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens)
    → compute tokensRemaining = planLimit - tokensUsed
    → compute windowEnd = most recent windowStart + windowDuration
    → returns WindowUsage
    ↓
await MainActor.run { appModel.windowStats = result }
    ↓
SwiftUI re-renders MenuBarView, WindowUsageView [main thread]
```

### State Management Flow

```
AppModel (@Observable, owned by App via @State)
    ↓ .environment(appModel)
MenuBarView
    ↓ reads appModel.windowStats, appModel.weeklyStats
WindowUsageView (x2)
    receives WindowUsage value — no direct model access
```

### Key Data Flows

1. **Initial load:** App launch triggers `UsageService.refresh()` immediately (not waiting for first timer tick), so data is available before user opens the dropdown.
2. **Continuous polling:** Timer fires every 30 seconds, re-scanning all JSONL files. No incremental diffing — full re-read each cycle. Acceptable because log files are small and reads are fast.
3. **Settings toggle:** `SettingsView` reads/writes `SMAppService.mainApp.status` directly — not routed through `AppModel`. This is appropriate because launch-at-login is a system setting, not an app state.

## Suggested Build Order

Dependencies flow bottom-up. Build data layer first, UI last.

1. **Models** (`UsageEntry`, `WindowUsage`, `TimeWindow`) — no dependencies; testable immediately.
2. **JSONLParser** — depends only on `UsageEntry`; test with a fixture `.jsonl` file.
3. **LogFileScanner** — depends on `FileManager`; test against actual `~/.claude/` directory.
4. **UsageAggregator** — depends on `UsageEntry`, `WindowUsage`, `TimeWindow`; pure logic, highly testable.
5. **AppModel** — depends on `WindowUsage`; wire up the `@Observable` state shape.
6. **UsageService** — depends on scanner, parser, aggregator, `AppModel`; integration layer.
7. **WindowUsageView** — depends on `WindowUsage`; renders one progress bar row; preview with stub data.
8. **MenuBarView** — depends on `AppModel`, `WindowUsageView`; top-level popover layout.
9. **ClaudeUsageApp** — wires `MenuBarExtra` + `Settings` scenes; `LSUIElement` in Info.plist.
10. **SettingsView** + `SMAppService` — launch-at-login toggle; last because it requires an installed app to test.

## Anti-Patterns

### Anti-Pattern 1: Using .menu Style for the Dropdown

**What people do:** Leave `MenuBarExtra` at its default `.menu` style to get "native" menu behavior.

**Why it's wrong:** The default menu style only supports `Button`, `Divider`, and `Menu` primitives. It cannot render `ProgressView`, `Gauge`, or arbitrary layout. The app's core feature (progress bars) is impossible with this style.

**Do this instead:** Set `.menuBarExtraStyle(.window)` and size the panel explicitly (e.g., `.frame(width: 320, height: 200)`).

### Anti-Pattern 2: Parsing JSONL on the Main Thread

**What people do:** Trigger file reads inside a `View.onAppear` or `Button` action directly (no `Task` wrapper).

**Why it's wrong:** File I/O, even for small files, can block the main thread. With `MenuBarExtra(.window)` style, the window renders on the main thread — any blocking work causes visible jank when the popover opens.

**Do this instead:** All file operations live in `UsageService`, run via `Task.detached(priority: .background)`, and publish results back via `await MainActor.run { }`.

### Anti-Pattern 3: Storing AppModel in a Singleton

**What people do:** Create a `shared` static instance on `AppModel` to avoid passing it through the environment.

**Why it's wrong:** Singletons make testing harder and hide dependencies. SwiftUI's `@Environment` is designed exactly for this — one model instance, injected at the scene boundary, available throughout the view tree.

**Do this instead:** Create the model with `@State` in the `App` struct and inject via `.environment(appModel)`. Access in views with `@Environment(AppModel.self)`.

### Anti-Pattern 4: Using SettingsLink Inside MenuBarExtra

**What people do:** Add a `SettingsLink` button inside the dropdown to open a preferences window.

**Why it's wrong:** `SettingsLink` does not work reliably inside `MenuBarExtra`. The control assumes a main window context that menu bar apps don't have. This is a documented Apple framework gap as of 2025.

**Do this instead:** If settings are needed, use `openWindow(id:)` with a dedicated `Window` scene, or handle via a direct `NSApp.sendAction(Selector("showSettingsWindow:"))` call with activation policy juggling (accept the complexity or skip a dedicated settings window entirely for a simple app).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| `~/.claude/projects/` | `FileManager.enumerator` — read-only; no entitlements needed for non-sandboxed personal app | JSONL files; no write access required |
| `SMAppService` (ServiceManagement) | Import `ServiceManagement`; call `mainApp.register()` / `mainApp.unregister()` | macOS 13+ only; check `.status` on every `onAppear` since user can change it in System Settings |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `UsageService` ↔ `AppModel` | Direct property write via `@MainActor` | Service holds a weak reference to model |
| `LogFileScanner` ↔ `JSONLParser` | `[URL]` passed as value; `JSONLParser` is stateless | Scanner calls parser per file; no shared state |
| `AppModel` ↔ `MenuBarView` | SwiftUI `@Environment` injection | Model injected at `MenuBarExtra` scene level |
| `UsageAggregator` ↔ `TimeWindow` | `TimeWindow` enum provides window duration + plan token limit constants | Centralizes limit values; change one place when plan limits change |

## Scaling Considerations

This is a single-user local app. Scaling in the traditional sense does not apply. The relevant axis is data volume:

| Log Volume | Architecture Adjustments |
|-----------|--------------------------|
| < 10,000 entries (normal usage) | Full re-read every 30s is fine; no optimization needed |
| 10,000–100,000 entries (months of logs) | Consider reading only files modified in the last 7 days; use `URLResourceKey.contentModificationDateKey` in `FileManager.enumerator` to skip old files |
| > 100,000 entries | Cache last-parsed state keyed by (file URL, modification date); only re-parse changed files |

### Scaling Priorities

1. **First bottleneck:** File enumeration across many project directories. Fix: filter by modification date before reading.
2. **Second bottleneck:** Parsing large individual files. Fix: incremental parse using file offsets stored in `UserDefaults` between runs.

## Sources

- [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/menubarextra) — HIGH confidence
- [MenuBarExtraStyle — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/menubarextrastyle) — HIGH confidence
- [Build a macOS menu bar utility in SwiftUI — nilcoalescing.com](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — HIGH confidence
- [What I Learned Building a Native macOS Menu Bar App — dev.to](https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6) — MEDIUM confidence (practitioner experience)
- [Showing Settings from macOS Menu Bar Items — steipete.me (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — HIGH confidence (documents SettingsLink gap)
- [Add launch at login setting — nilcoalescing.com](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — HIGH confidence (SMAppService pattern)
- [How to Read / Write JSONL Files in Swift — natashatherobot.com](https://www.natashatherobot.com/p/read-write-jsonl-files-swift) — MEDIUM confidence
- [SwiftUI's @Observable macro — jessesquires.com](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/) — HIGH confidence
- [FileManager.DirectoryEnumerator — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerator) — HIGH confidence

---
*Architecture research for: Native macOS SwiftUI menu bar token usage tracker*
*Researched: 2026-03-11*
