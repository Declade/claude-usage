# Project Research Summary

**Project:** Claude Usage — macOS menu bar token usage tracker
**Domain:** Native macOS menu bar utility (Swift/SwiftUI, local JSONL file reading)
**Researched:** 2026-03-11
**Confidence:** HIGH

## Executive Summary

This is a native macOS menu bar utility that reads Claude Code's local JSONL usage logs from `~/.claude/projects/**/*.jsonl` and displays token consumption against the 4-hour rolling window and weekly limits. The entire competitive landscape of similar tools relies on browser-based API auth or third-party endpoints — this app's decisive differentiator is zero-auth, zero-network, local-file-only operation. It reads data Claude Code already writes; no credentials or permissions beyond disabling the App Sandbox are required.

The recommended approach is pure Swift 6 + SwiftUI using `MenuBarExtra` with `.menuBarExtraStyle(.window)` for the dropdown panel, `Foundation` for JSONL parsing (no third-party dependencies), `Timer`-based polling at 30–60 second intervals for refresh, and `SMAppService` for launch-at-login. The architecture separates cleanly into three layers: data (LogFileScanner → JSONLParser → UsageAggregator), state (`@Observable AppModel`), and UI (MenuBarView + WindowUsageView). All file I/O runs on a background task; only final aggregated values are dispatched to `@MainActor`.

The top risks are architectural mistakes made at project inception: using the wrong `MenuBarExtra` style (`.window` feels like a floating utility, not a native menu), leaving the App Sandbox enabled (silently blocks `~/.claude/` reads in non-debug builds), and doing file I/O on the main thread (stutters on large log files). All three must be locked correctly in Phase 1 before any business logic is written. The rolling window calculation also carries a persistent risk of timezone-related off-by-one errors that require explicit unit tests to catch.

## Key Findings

### Recommended Stack

The entire app builds on macOS SDK frameworks with no SPM dependencies. Swift 6 language mode (Xcode 16, Swift 6.1) with `@MainActor` isolation is the correct default — keep it, do not opt back to Swift 5 mode. The minimum deployment target is macOS 13.0 (Ventura): `MenuBarExtra` requires it, `SMAppService` requires it, and Ventura/Sonoma/Sequoia covers ~95%+ of active developer machines as of early 2026. The `@Observable` macro (macOS 14+) is preferred over `ObservableObject`; if macOS 13 compatibility is needed for a broader audience, fall back to `@ObservedObject` + `@Published`.

**Core technologies:**
- Swift 6.1 / Xcode 16: Language — Swift 6 concurrency mode gives safe `@MainActor` UI isolation by default
- SwiftUI `MenuBarExtra` (.window style): Menu bar presence — canonical modern API, no AppKit scaffolding needed; requires macOS 13+
- Foundation `FileManager` + `String(contentsOf:)` + `JSONDecoder`: JSONL parsing — built-in, no external library adds value
- Foundation `Timer` / `Task.sleep`: Polling at 30–60s — FSEvents is over-engineering for this data access frequency
- `ServiceManagement.SMAppService`: Launch at login — only non-deprecated API on macOS 13+; replaces `SMLoginItemSetEnabled`

### Expected Features

**Must have (table stakes for v1):**
- Menu bar icon with compact usage indicator (progress bar or percentage) — the app's entire reason for existing
- Left-click popover showing both windows (4-hour + weekly) with used/remaining/reset time
- JSONL log parser reading all four token types (input, output, cache_creation, cache_read)
- Reset window calculator for the 4-hour rolling window and weekly boundary
- Auto-refresh via polling (30–60 second interval) — stale data breaks trust
- `LSUIElement = YES` in Info.plist, light/dark icon adaptation, Quit menu item — macOS convention compliance

**Should have (add after v1 is working daily):**
- Threshold notifications at a configurable percentage (80%, 95%) — addresses the "surprise cutoff" pain point
- Launch at login toggle — needed for the app to survive reboots
- Pace indicator (on-track / at-risk) — transforms data from descriptive to actionable using existing log data
- Cache token visibility in the detail view — low effort, data is already parsed

**Defer (v2+):**
- FSEvents file watcher — only matters if 30s polling latency is felt by users
- Per-session breakdown — adds display complexity; validate demand first
- In-popover settings section — only worth building when there are enough settings to warrant it

The key competitive insight: every competitor requires authentication. Reading local JSONL files is simpler, more robust, and the right bet for a personal tool.

### Architecture Approach

The architecture follows a strict three-layer pattern with data flowing bottom-up: `LogFileScanner` discovers all `.jsonl` files, `JSONLParser` decodes them line-by-line into `UsageEntry` structs using `keyDecodingStrategy = .convertFromSnakeCase`, and `UsageAggregator` filters by time window and sums token counts into `WindowUsage` value types. `UsageService` owns the `Timer`, runs the full scan→aggregate cycle on a background `Task.detached`, then publishes results to `AppModel` via `await MainActor.run`. `AppModel` is an `@Observable` class owned by the `App` struct via `@State` and injected into the view tree via `.environment(appModel)`. Build in dependency order: Models → JSONLParser → LogFileScanner → UsageAggregator → AppModel → UsageService → Views → App entry point → SettingsView + SMAppService.

**Major components:**
1. `AppModel` (`@Observable`) — central state holder; owns `windowStats`, `weeklyStats`, `lastRefresh`; single source of truth for all views
2. `UsageService` — owns `Timer`; coordinates background scan→aggregate cycle; dispatches results to `AppModel` on `@MainActor`
3. `LogFileScanner` + `JSONLParser` + `UsageAggregator` — stateless data layer; pure functions; independently unit-testable
4. `MenuBarView` + `WindowUsageView` — SwiftUI views; read `AppModel` via environment; no direct model mutation
5. `ClaudeUsageApp` (`@main`) — declares `MenuBarExtra(.window)` scene; owns `AppModel` lifetime

### Critical Pitfalls

1. **Wrong MenuBarExtra style at project start** — `.window` style is the correct choice for progress bar content, but it has known quirks (no programmatic close, slight open delay). Commit to this style in Phase 1 and accept the quirks; the alternative (`NSMenu + NSHostingView`) requires a full UI rewrite to adopt later. If native-feel is paramount, evaluate `fluid-menu-bar-extra` as a hybrid pattern before writing any UI code.

2. **App Sandbox enabled in Xcode project** — Sandbox blocks `~/.claude/` reads in any non-debug build scheme, silently returning empty data. Disable `com.apple.security.app-sandbox` in the entitlements file from day one. This is documented as the correct choice for a non-App Store personal tool. Verify the setting in the *archive* build, not just the debug run.

3. **File I/O on the main thread** — Even `String(contentsOf:)` on a small JSONL file will cause perceptible jank if called synchronously from a `View.onAppear` or `Timer` callback on the main thread. All file operations must live in `Task.detached(priority: .background)` from the first line of polling code written.

4. **Timezone errors in window calculation** — The 4-hour window is a rolling window anchored to `Date.now - 14400s`, not a calendar boundary. Use `ISO8601DateFormatter` to parse timestamps (produces UTC-anchored `Date`), compute the window boundary as pure `TimeInterval` math (no `Calendar.current`), and write unit tests that verify correct inclusion/exclusion of entries spanning UTC midnight.

5. **Missing cache token fields in aggregation** — The usage total must sum all four token fields: `input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Omitting the cache fields silently underreports usage, especially for projects with high cache hit rates. Add an explicit assertion in unit tests.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Core Scaffold
**Rationale:** Three pitfalls (wrong MenuBarExtra style, App Sandbox, Dock icon flash) must be locked correctly before any business logic is written. These are architectural foundation decisions with high rewrite cost if deferred.
**Delivers:** A running macOS app with a menu bar icon that opens an empty popover panel, no Dock icon, correct entitlements, and correct project structure. No data yet.
**Addresses:** FEATURES.md "No Dock icon", macOS convention compliance
**Avoids:** Pitfall 1 (wrong MenuBarExtra style), Pitfall 2 (App Sandbox), Pitfall 5 (Dock icon flash via `LSUIElement`)

### Phase 2: Data Layer — JSONL Parsing and Token Aggregation
**Rationale:** The JSONL parser and aggregator are the foundation of every data-bearing feature. All P1 features depend on them. Building data layer before UI ensures the foundation is tested before it is wired to views.
**Delivers:** `UsageEntry`, `WindowUsage`, `TimeWindow` models; `JSONLParser`, `LogFileScanner`, `UsageAggregator` — fully unit-tested with fixture JSONL files including edge cases (blank lines, partial entries, timezone-boundary entries, cache token fields).
**Uses:** Foundation `FileManager`, `JSONDecoder`, `ISO8601DateFormatter`
**Implements:** Data layer components from ARCHITECTURE.md
**Avoids:** Pitfall 3 (main-thread I/O, via background Task from the start), Pitfall 4 (timezone errors, via unit tests), Pitfall: cache token omission

### Phase 3: UsageService, AppModel, and UI Wiring
**Rationale:** Once the data layer is solid, wire up the Timer-based polling service and connect it to the `@Observable` model. Then build the MenuBarView and WindowUsageView against real data. UI-first development here would require stub data scaffolding that gets thrown away.
**Delivers:** A fully functional app that displays live 4-hour and weekly window progress bars, token counts, and reset timers. Auto-refreshes every 30 seconds. Meets the complete v1 MVP definition.
**Uses:** SwiftUI `ProgressView`, `MenuBarExtra(.window)`, `@Observable`, `@MainActor`
**Implements:** `UsageService` (Timer loop + background Task), `AppModel`, `MenuBarView`, `WindowUsageView`
**Avoids:** Pitfall 6 (stale counts on menu open — add `NSMenu`-delegate-style immediate refresh on popover show), Pitfall 7 (non-template status bar icon)

### Phase 4: Polish and Persistence Features
**Rationale:** With the core working and used daily, add the v1.x features: launch at login, threshold notifications, pace indicator, and cache token visibility. These are independent of each other and can be added in any order.
**Delivers:** Launch at login toggle, configurable threshold notifications, on-track/at-risk pace indicator, cache token breakdown in detail view. The app is complete for daily personal use.
**Uses:** `SMAppService`, `UserNotifications`, pace projection logic against existing `UsageEntry` data
**Implements:** `SettingsView` + SMAppService integration, `NotificationService`, pace calculation in `UsageAggregator`

### Phase Ordering Rationale

- **Data before UI:** Architecture research explicitly recommends building bottom-up (Models → Parser → Aggregator → Service → Views). Skipping this order produces untestable code and forces stub scaffolding.
- **Foundation before features:** All three highest-severity pitfalls (MenuBarExtra style, App Sandbox, main-thread I/O) must be resolved in Phase 1 and 2 before any feature work. These are not "fix later" items — they require rewrites to fix after the fact.
- **Pitfall-to-phase alignment:** PITFALLS.md explicitly maps each pitfall to a phase. This roadmap structure follows that mapping exactly.
- **v1.x features decoupled:** Launch at login is fully independent of data features (per FEATURES.md dependency tree). Notifications require the 4-hour window calculation as a prerequisite. Both land in Phase 4 after the core is validated.

### Research Flags

Phases with standard, well-documented patterns (research-phase not needed):
- **Phase 1:** Standard macOS app scaffold; `LSUIElement`, `MenuBarExtra`, entitlements configuration are all documented in official Apple docs and verified community sources
- **Phase 2:** JSONL parsing pattern with `String.split` + `JSONDecoder` is straightforward Foundation usage; unit testing strategy is standard
- **Phase 3:** `@Observable` + SwiftUI view wiring follows Apple's documented patterns; `Timer` + background Task threading model is well-established

Phases that may benefit from targeted research during planning:
- **Phase 4 — Threshold Notifications:** `UserNotifications` in a menu bar app (no main window) has edge cases around permission request timing and foreground vs. background delivery. Worth a focused look before implementation.
- **Phase 4 — SMAppService:** Login item registration can silently fail on first attempt; PITFALLS.md notes this. The "Looks Done But Isn't" checklist item requires a reboot test. No new research needed, but the implementation checklist must include this test.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommendations backed by official Apple Developer Documentation; Swift 6.1/Xcode 16 is current stable; MenuBarExtra and SMAppService are documented APIs |
| Features | HIGH | Multiple real competing implementations analyzed; user pain points documented from community posts; table stakes list is conservative and well-validated |
| Architecture | HIGH | Patterns verified against official SwiftUI docs, nilcoalescing.com (authoritative community source), and steipete.me post-mortem. Build order and component boundaries are unambiguous |
| Pitfalls | HIGH | All 7 critical pitfalls sourced from official docs, confirmed feedback reports (FB13683950, FB11984872), and real-world post-mortems. Multiple independent sources agree on each finding |

**Overall confidence:** HIGH

### Gaps to Address

- **Exact token limit values for the 4-hour and weekly windows:** PITFALLS.md flags hardcoded limits (e.g., 44,000 / 7,000,000) as technical debt because Anthropic changes these. The correct approach is to read limits from a config source, but the specific current limit values and any available programmatic source are not confirmed in research. Address during Phase 2 planning: check if Claude Code writes limit metadata to the JSONL files or a separate config file; if not, use a user-editable defaults file.

- **`@Observable` vs. `ObservableObject` target floor decision:** `@Observable` requires macOS 14. `MenuBarExtra` requires macOS 13. If the deployment target stays at macOS 13.0, `@Observable` is unavailable for the small slice of Ventura users. Architecture research notes this and recommends `@Observable` (implying accepting macOS 14 as the effective floor) or falling back to `ObservableObject`. Decide during Phase 1 scaffold and document the choice.

- **JSONL file schema stability:** Research confirms the local JSONL approach works and the field names are known, but Claude Code is actively developed software. If Anthropic changes the log schema, the parser breaks silently (fields decode as nil). Consider adding a schema version check or a "last successful parse" indicator in the UI to surface this failure mode.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — MenuBarExtra, MenuBarExtraStyle, SMAppService, FileManager, FileSystemEvents
- Apple Developer Documentation — App Sandbox, Accessing Files from the macOS App Sandbox
- Xcode 16.4 Release Notes — Swift 6.1, macOS Sequoia 15.5 SDK

### Secondary (MEDIUM confidence)
- nilcoalescing.com — Build a macOS menu bar utility in SwiftUI; Add launch at login setting
- steipete.me — Showing Settings from macOS Menu Bar Items: A 5-Hour Journey (2025)
- jessesquires.com — SwiftUI's @Observable macro
- natashatherobot.com — How to Read/Write JSONL Files in Swift
- troz.net — The Mac Menubar and SwiftUI (2025)
- bjango.com — Designing macOS menu bar extras (template image requirements)

### Tertiary (MEDIUM-LOW confidence, corroborated)
- feedback-assistant/reports FB13683950 — MenuBarExtra missing open callback (confirmed limitation)
- feedback-assistant/reports FB11984872 — MenuBarExtra .window style missing programmatic close
- DEV Community — What I Learned Building a Native macOS Menu Bar App (NSPopover pain points, sandbox restrictions)
- GitHub: hamed-elfayome/Claude-Usage-Tracker — competitor feature baseline
- GitHub: tddworks/ClaudeBar, masorange/ClaudeUsageTracker — competitor pattern analysis
- DEV Community — I got tired of hitting AI rate limits mid-task (user pain point validation)
- preslav.me — Claude Code token usage on macOS toolbar (JSONL approach community validation)

---
*Research completed: 2026-03-11*
*Ready for roadmap: yes*
