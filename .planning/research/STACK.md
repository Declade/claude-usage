# Stack Research

**Domain:** macOS menu bar utility app (Swift/SwiftUI)
**Researched:** 2026-03-11
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.1 (Xcode 16.4) | Language | Current stable release shipped with Xcode 16. Swift 6 concurrency mode with MainActor isolation is the right default for UI apps in 2025. |
| SwiftUI | macOS 13+ API surface | UI framework | Declarative views, native look. MenuBarExtra (introduced macOS 13) is the canonical modern approach — no AppKit scaffolding needed. |
| MenuBarExtra (SwiftUI scene) | macOS 13+ | Menu bar presence | Introduced at WWDC 2022, ships in macOS Ventura. The correct SwiftUI-native replacement for hand-rolling NSStatusBar. Use `.menuBarExtraStyle(.window)` for a popover-panel UI (progress bars, labels); use `.menuBarExtraStyle(.menu)` only for pure menu lists. |
| Foundation (FileManager + String) | macOS 13+ | JSONL file reading | Built-in. Read file contents with `String(contentsOf:encoding:)`, split on `\n`, decode each line with `JSONDecoder`. No third-party dependency needed. |
| Foundation (Timer / async Task.sleep) | macOS 13+ | Polling refresh | A repeating `Timer.scheduledTimer` or an `async` loop with `Task.sleep(for:)` is the right tool for low-frequency polling (every 30–60 s). FSEvents is overkill for this use case — see rationale below. |
| ServiceManagement (SMAppService) | macOS 13+ | Launch at login | Apple's modern API introduced in Ventura. `SMAppService.mainApp.register()` / `.unregister()`. Replaces the deprecated `SMLoginItemSetEnabled`. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| None required | — | — | This app has no network calls, no database, and no complex UI. Adding SPM dependencies for a 300-line app increases maintenance surface with zero benefit. Use only what ships with the OS. |

> If a dependency becomes necessary later, evaluate [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) (for programmatic show/hide of the MenuBarExtra popover) — it is a thin, focused package.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16 | IDE, build, signing | Required. Use macOS 13.0 as deployment target (see rationale). Swift 6 language mode is default in new projects — keep it. |
| Instruments (Time Profiler) | CPU and memory profiling | Menu bar apps must be extremely light. Profile before shipping. |
| Console.app | Log inspection | Use `Logger` (os.log) not `print()` for runtime diagnostics — Console.app filters by subsystem. |

## Installation

This is a native Swift app — there are no `npm install` steps. The full setup is:

```bash
# 1. Open Xcode → File → New Project → macOS → App
# 2. Set deployment target to macOS 13.0 in project settings
# 3. In Info.plist, add:
#    LSUIElement = YES  (hides Dock icon)
#    NSPrincipalClass = NSApplication
# 4. No SPM dependencies to add for v1
```

Code-sign with your personal Apple Developer certificate for local/ad-hoc use. No App Store submission — no sandbox entitlements required.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| MenuBarExtra (.window style) | NSStatusBar + NSStatusItem + NSPopover | If targeting macOS 12 Monterey or earlier. Otherwise MenuBarExtra is strictly better — less boilerplate, full SwiftUI state management. |
| MenuBarExtra (.window style) | NSStatusBar + NSMenu | Only for pure-menu list UIs (no custom views). Not appropriate here: we need progress bars, which require custom SwiftUI views in a window-style panel. |
| Timer / async sleep polling | FSEvents (CoreServices) | Use FSEvents if watching hundreds of files or if sub-second latency matters. For this app: Claude Code writes usage logs at most once per API call, and a 30-second poll is invisible to the user. FSEvents adds 40+ lines of C-callback bridge code for zero user-visible benefit. |
| SMAppService | LoginItems (older APIs, `LSSharedFileList`) | SMAppService is the only non-deprecated launch-at-login API on macOS 13+. Do not use `SMLoginItemSetEnabled` — it is deprecated since macOS 13. |
| Non-sandboxed (no entitlements) | Sandboxed app | App Store distribution requires sandboxing. For personal/local use, sandboxing blocks direct access to `~/.claude/` without a user file-picker flow every launch. Since this app is not App Store bound, disable the App Sandbox capability entirely in Xcode signing settings. |
| Foundation Codable + String.split | Third-party JSONL library | No mature, maintained Swift JSONL library exists that adds value over `String.split(separator: "\n")` + `JSONDecoder`. Keep it in Foundation. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| NSPopover (manual) | Feels like a "floating app" — slight delay, doesn't dismiss naturally, no native system integration. Many developers regret starting here. | MenuBarExtra with `.menuBarExtraStyle(.window)` — system manages presentation/dismissal, respects Accessibility settings. |
| Electron / web stack | 150–400 MB RAM baseline for a status bar widget. No native menu bar integration. | Swift/SwiftUI — 5–15 MB RAM for this use case. |
| SettingsLink inside MenuBarExtra | Known broken: `SettingsLink` does not work reliably inside a `MenuBarExtra` scene. The Settings/Preferences window requires activation policy juggling and timing hacks if opened from a menu bar panel. | If settings are needed, open a dedicated `Settings` scene from a dedicated `MenuBarExtra` label action, or use `NSApp.activate()` + `openSettings` environment action with care. |
| Hardcoded paths (`/Users/[name]/.claude`) | Non-portable. Will break on other machines. | `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")` |
| Swift 5 concurrency mode (explicitly disabled) | Swift 6 concurrency mode is the default in Xcode 16. Opting back to Swift 5 mode trades safety for short-term convenience and creates future migration debt. | Keep Swift 6 mode. Use `@MainActor` on the ViewModel. File I/O runs in a `Task { }` or background actor. |
| Polling interval under 15 seconds | Claude Code API calls happen at human interaction speed. 15–30 seconds is invisible to the user. Sub-15s polling wastes CPU/battery with zero benefit. | `Timer.scheduledTimer(withTimeInterval: 30, repeats: true)` |

## Stack Patterns by Variant

**For the menu bar label (always-visible token summary):**
- Use the `label:` parameter of `MenuBarExtra` — it accepts a SwiftUI `View`, so a custom `Canvas`-drawn mini progress bar is possible here.
- Because `MenuBarExtra` label refreshes are driven by `@StateObject` / `@ObservedObject`, the standard `ObservableObject` + `@Published` pattern is sufficient.

**For the dropdown panel (full stats view):**
- Use `.menuBarExtraStyle(.window)` to render a `VStack` with two `ProgressView` rows, token counts, and reset timers.
- Keep the panel narrow (280–320 pt) — menu bar popover panels wider than the screen look broken on small laptops.

**If polling proves unreliable (missed writes):**
- Swap the `Timer` for a `DispatchSourceFileSystemObject` (kqueue-based) watch on the `~/.claude/projects/` directory. This is simpler and more portable than FSEvents for directory-level change detection.

## Version Compatibility

| Component | Minimum | Notes |
|-----------|---------|-------|
| MenuBarExtra | macOS 13.0 (Ventura) | Introduced WWDC 2022. Not available on macOS 12 or earlier. |
| SMAppService | macOS 13.0 (Ventura) | Replaces deprecated SMLoginItemSetEnabled. Same minimum as MenuBarExtra — no separate floor needed. |
| Swift 6 language mode | Xcode 16+ | Ships with macOS Sequoia SDK. Fully compatible with macOS 13.0 deployment target. |
| async/await + Task | macOS 10.15 (Catalina) | Available well below our deployment floor — no availability guards needed. |
| `String(contentsOf:encoding:)` | macOS 10.0+ | Foundation primitive, no version concerns. |

**Deployment target recommendation: macOS 13.0 (Ventura)**

Rationale: MenuBarExtra and SMAppService both require macOS 13. As of early 2026, Ventura, Sonoma, and Sequoia are the three actively supported macOS versions (matching Apple's implicit "current + 2 prior" support window). Setting 13.0 captures ~95%+ of active Macs in developer households without any compatibility shims.

## Sources

- Apple Developer Documentation — [MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — HIGH confidence (official)
- Apple Developer Documentation — [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — HIGH confidence (official)
- Apple Developer Documentation — [File System Events](https://developer.apple.com/documentation/coreservices/file_system_events) — HIGH confidence (official)
- [Xcode 16.4 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_4-release-notes) — Swift 6.1, macOS Sequoia 15.5 SDK — HIGH confidence
- [nilcoalescing.com — Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MenuBarExtra patterns — MEDIUM confidence (verified against Apple docs)
- [steipete.me — Showing Settings from macOS Menu Bar Items: A 5-Hour Journey](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — SettingsLink gotcha, NSPopover limitations — MEDIUM confidence (real-world 2025 experience)
- [Natasha the Robot — How to Read/Write JSONL Files in Swift](https://www.natashatherobot.com/p/read-write-jsonl-files-swift) — JSONL parsing pattern — MEDIUM confidence
- [nilcoalescing.com — Add launch at login setting](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — SMAppService usage — MEDIUM confidence (verified against Apple docs)
- [DEV Community — What I Learned Building a Native macOS Menu Bar App](https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6) — NSPopover pain points — LOW confidence (single community post, corroborated by steipete)

---
*Stack research for: Claude Usage — macOS menu bar token usage tracker*
*Researched: 2026-03-11*
