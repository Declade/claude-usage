# Pitfalls Research

**Domain:** Native macOS menu bar app — SwiftUI/AppKit, local JSONL log reading, time-windowed token tracking
**Researched:** 2026-03-11
**Confidence:** HIGH (all findings verified via official Apple docs, community post-mortems, and multi-source agreement)

---

## Critical Pitfalls

### Pitfall 1: Choosing .window Style for the MenuBarExtra Popup

**What goes wrong:**
`MenuBarExtra` with `.menuBarExtraStyle(.window)` renders a floating SwiftUI window that looks and behaves like a "floating app" rather than a native system utility. It has a slight delay on open, does not auto-dismiss when the user clicks elsewhere reliably, and lacks native macOS menu animations. There is no 1st-party API to programmatically close the window from within the content view.

**Why it happens:**
SwiftUI's MenuBarExtra arrived in macOS Ventura and the `.window` style is the most "SwiftUI-native" option — it lets you drop in any SwiftUI view tree. Tutorials default to it because it requires zero AppKit. Developers only discover its inadequacies after shipping.

**How to avoid:**
Use `NSMenu` with `NSHostingView` for the popup content, or use the `.menu` style and accept its constraints (text/buttons/dividers only, no images, no sliders). For a progress-bar-heavy dropdown, `NSMenu + NSHostingView` gives you custom SwiftUI views with native open/close behavior. The `fluid-menu-bar-extra` open-source project (lfroms/fluid-menu-bar-extra) provides a tested pattern for this hybrid approach.

**Warning signs:**
- Popup content contains SwiftUI views with sliders, progress bars, or custom styling
- App feels like a "floating utility window" rather than a menu
- Users report that clicking outside the popup does not reliably dismiss it

**Phase to address:**
Phase 1 (Core scaffold). Architecture decision must be locked before any UI is built on top of it.

---

### Pitfall 2: Reading ~/.claude/ Files from a Sandboxed App

**What goes wrong:**
If the App Sandbox is enabled (required for Mac App Store distribution), `FileManager.default.homeDirectoryForCurrentUser` returns the app's sandbox container, not the real `~` directory. Attempts to read `~/.claude/projects/` silently return empty or throw permission-denied errors. The app builds and runs fine in development (where Xcode signs without sandbox) but fails for any sandboxed distribution.

**Why it happens:**
The PROJECT.md states "no special entitlements needed for sandboxed reads of home directory files" — this is incorrect for sandboxed apps. The sandbox isolates the app's home view. Developers test without sandbox, ship with sandbox, and discover the issue after release.

**How to avoid:**
Since this app is "local build / personal use — no App Store submission required" (per PROJECT.md), disable the App Sandbox entirely in the entitlements file. Set `com.apple.security.app-sandbox` to `false`. This is the correct choice for a personal utility not targeting the App Store. Document this decision explicitly in the entitlements file so future contributors do not re-enable sandbox thinking it is a security improvement.

If App Store distribution is ever required, use `com.apple.security.temporary-exception.files.home-relative-path.read-only` with the path `/.claude/` — but App Review scrutinizes this entitlement heavily.

**Warning signs:**
- App Sandbox entitlement is enabled (check project `.entitlements` file)
- `URL(fileURLWithPath: NSHomeDirectory())` returns a path inside `~/Library/Containers/`
- File reads return empty data in release builds but work in debug

**Phase to address:**
Phase 1 (Core scaffold). Entitlements must be configured correctly before any file-reading code is written.

---

### Pitfall 3: Blocking the Main Thread with Full-File JSONL Reads on Each Refresh

**What goes wrong:**
The naive implementation reads every `.jsonl` file in `~/.claude/projects/` from scratch on each polling interval — loading the entire file into memory, splitting by newline, and decoding each JSON object. For large projects with thousands of log entries, this stalls the main thread, causes the menu bar item to freeze or stutter, and wastes CPU/battery on re-processing lines that have not changed.

**Why it happens:**
JSONL files are append-only. The simplest implementation ignores this property and treats the file like a static JSON file to be re-decoded in full. When files are small during development, the problem is invisible.

**How to avoid:**
Track the last-read byte offset per file using `FileHandle.seekToEndOfFile()` / `seek(toFileOffset:)`. On each polling cycle, only read bytes appended since the last offset. Parse only the new lines. Keep a running aggregate of token counts in memory — never re-sum the entire history on each tick. Do all file I/O and JSON decoding on a background `Task` or `DispatchQueue`, then `@MainActor`-dispatch only the final aggregated counts to update the UI.

**Warning signs:**
- Polling is implemented as `Timer.scheduledTimer` with a `URL(contentsOf:)` call on the main queue
- No byte-offset tracking exists in the data model
- CPU spikes visible in Activity Monitor on each poll interval

**Phase to address:**
Phase 2 (File reading and token aggregation). The incremental-read pattern must be established before wiring up the UI.

---

### Pitfall 4: Off-by-One Errors in the 4-Hour Rolling Window Calculation

**What goes wrong:**
The "current 4-hour reset window" is a rolling window, not a fixed clock boundary (e.g. not "midnight to 4am"). Calculating it as `Date.now - 4 hours` is correct, but developers often make subtle errors: comparing timestamps without normalizing timezone offsets, using `Calendar.current` (which applies local timezone) when the JSONL timestamps are ISO 8601 UTC strings, or comparing `Date` objects that were constructed with implicit local timezone assumptions.

A secondary mistake: not anchoring "weekly reset" to the correct weekday/time boundary that Anthropic uses, treating it as simply "7 days ago."

**Why it happens:**
Swift's `Date` type stores UTC seconds since reference date — timezone-agnostic. But `DateFormatter`, `Calendar`, and `DateComponents` all apply the system local timezone by default. Mixing these produces silent one-to-several-hour errors, which are hard to detect in development if the developer is in UTC+0 or does not test across daylight saving transitions.

**How to avoid:**
Parse JSONL timestamps using `ISO8601DateFormatter` (which parses to UTC-anchored `Date` correctly). For the rolling window boundary, compute purely as `Date.now.addingTimeInterval(-4 * 3600)` — no calendar arithmetic needed. Do not use `Calendar.current` for this calculation. Add a unit test that constructs synthetic log entries spanning a timezone boundary (UTC midnight) and verifies correct inclusion/exclusion.

**Warning signs:**
- Token counts are "off by about an hour" for users in non-UTC timezones
- `DateFormatter` is used to parse JSONL timestamps instead of `ISO8601DateFormatter`
- No unit tests for the window boundary calculation

**Phase to address:**
Phase 2 (Token aggregation logic). Write tests alongside the calculation, not after.

---

### Pitfall 5: App Activation Policy Causes Dock Icon Flash on Launch

**What goes wrong:**
Menu bar apps should not appear in the Dock. Setting `NSApp.setActivationPolicy(.accessory)` programmatically in `applicationDidFinishLaunching` causes a brief (0.5–1s) Dock icon flash at every launch because the app starts as `.regular` policy (showing in Dock), then switches. Additionally, apps with `.accessory` policy are treated as background utilities by the OS — they do not become the frontmost app when the user clicks them or opens the popup, which breaks `NSWindow` ordering for any preferences/settings window you later add.

**Why it happens:**
The correct way to suppress the Dock icon is `LSUIElement = YES` in `Info.plist`, not `setActivationPolicy`. Developers find the programmatic API first and ship it. The Dock flash is noticed only by meticulous testers.

**How to avoid:**
Set `LSUIElement` to `YES` (boolean) in `Info.plist`. This suppresses the Dock icon and app switcher appearance from process start with no flash. When a settings/preferences window needs to come to front (requiring `.regular` temporarily), toggle `NSApp.setActivationPolicy(.regular)` only then, then restore `.accessory` after dismissal.

**Warning signs:**
- `Info.plist` does not contain `LSUIElement`
- `AppDelegate.applicationDidFinishLaunching` calls `NSApp.setActivationPolicy(.accessory)`
- A Dock icon flash is visible when launching the app during testing

**Phase to address:**
Phase 1 (Core scaffold). `Info.plist` must be correct from day one.

---

### Pitfall 6: No Update Trigger When the Menu Opens

**What goes wrong:**
Token counts shown in the popup are stale — they reflect the state at the last polling cycle, not the state at the moment the user clicks the menu bar icon. If the polling interval is 30 seconds, the user can see data that is nearly 30 seconds old. Worse, with `.menuBarExtraStyle(.menu)`, SwiftUI blocks the runloop while the menu is open — so polling timers do not fire during the open state, making counts permanently stale until the next open.

**Why it happens:**
There is no Apple 1st-party API to receive a callback when a `MenuBarExtra` opens. This is a known limitation filed as feedback FB13683950. Developers assume a background timer will keep data current, not realizing the runloop is blocked during menu presentation.

**How to avoid:**
Use `NSMenu`'s delegate method `menuWillOpen(_:)` to trigger an immediate data refresh when the user clicks the status item — before the menu displays content. This is the standard AppKit pattern. Alternatively, use a short polling interval (5–10 seconds) and accept slight staleness. For `NSHostingView`-based custom popups, the `NSPopover` delegate provides `popoverWillShow`.

**Warning signs:**
- Using `.menuBarExtraStyle(.menu)` style with a `Timer.publish` background timer as the sole update mechanism
- No `NSMenu` delegate is set
- Counts appear stale immediately after a Claude Code session ends

**Phase to address:**
Phase 3 (UI wiring and refresh logic). Must be addressed when connecting data model to the menu popup.

---

### Pitfall 7: Template Image Not Used for Menu Bar Icon

**What goes wrong:**
The status bar icon (the mini progress bar or icon next to it) appears as a solid black rectangle in Dark Mode or is barely visible in Light Mode. On macOS, the menu bar background color changes based on the desktop wallpaper brightness, independently of the system dark/light mode setting. A non-template PNG image will look correct sometimes and broken on other setups.

**Why it happens:**
Developers design the icon, export it as a PNG, and load it directly as `Image("icon")`. They test in their own system appearance and never see the breakage. Template images — where macOS ignores all color and uses only the alpha channel — are the correct approach but require the explicit flag `nsImage.isTemplate = true`.

**How to avoid:**
Always set `nsImage.isTemplate = true` on any `NSImage` used as the `NSStatusItem` button image. Design the icon as a monochrome asset (black with transparency). For the progress bar displayed directly in the status bar, render it as a template-compatible `NSImage` drawn in black, let the system tint it.

**Warning signs:**
- Status item image loaded directly as `Image("icon")` without AppKit bridge
- Icon image contains color (not monochrome)
- App looks correct in developer's setup but broken in screenshots from others

**Phase to address:**
Phase 3 (UI polish). Can be fixed at any time, but worth addressing before first use by others.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Full-file re-read on every poll | Simple implementation, no state to manage | CPU/memory waste grows linearly with log file size; stutters on large projects | Never — incremental reads are straightforward |
| Hardcoding token limit values (e.g. 44,000 / 7,000,000) | No configuration UI needed | Limits change; app silently shows wrong progress bars | MVP only — add a config file read in Phase 2 |
| `.menuBarExtraStyle(.window)` for rapid prototyping | Pure SwiftUI, fast to build | Requires rewrite to NSMenu when behavior feels wrong; no path forward within SwiftUI | Prototype only, never ship |
| `Timer.scheduledTimer` on main thread for polling | Simple, no concurrency needed | Blocks UI during file I/O; stutters at scale | Never — use `Task { }` with `@MainActor` dispatch |
| Skipping sandbox configuration in Xcode template | Nothing breaks in dev | Sandboxed build silently cannot read `~/.claude/`; breaks any future distribution attempt | Only acceptable if sandbox is explicitly disabled from day one |

---

## Integration Gotchas

Common mistakes when integrating with the local filesystem and macOS system APIs.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| JSONL file discovery | Hardcode `~/.claude/projects/` path as a string literal | Use `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")` — works correctly only when sandbox is disabled |
| JSONL line parsing | Use `JSONDecoder` on entire file content | Split on `\n`, decode each line individually; skip blank lines and lines that fail decode without crashing the whole parse |
| FSEvents / file watching | Watch individual files with kqueue (requires one file descriptor per file) | Use `DispatchSource.makeFileSystemObjectSource` on the directory, or a simple `Timer`-based poll — fewer moving parts |
| SMAppService (login item) | Store "launch at login" state in `UserDefaults` | Read state from `SMAppService.mainApp.status` — user can disable it in System Settings independently of your app |
| Status item rendering | Load `NSStatusBarButton.image` from an Asset Catalog PNG | Load as `NSImage`, set `.isTemplate = true`, then assign — ensures correct dark/light rendering |

---

## Performance Traps

Patterns that work at small scale but fail as log files grow.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full re-read of all `.jsonl` files per poll | CPU spike every N seconds visible in Activity Monitor; occasional UI stutter | Track byte offsets; only read appended bytes | Once any single `.jsonl` file exceeds ~500KB (~5,000 entries) |
| Decoding all fields from every log entry | Memory grows proportional to session history | Decode only `timestamp`, `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` | Negligible at small scale; wasteful at thousands of entries |
| Re-summing all tokens on every UI refresh | CPU usage proportional to total session history | Maintain running sum; only add delta from new lines | Once a session has > ~10,000 entries |
| Short polling interval (< 5s) with file I/O on main thread | Consistent high CPU; UI feels sluggish | Use background `Task`; dispatch only result to `@MainActor` | Immediately |

---

## Security Mistakes

Domain-specific security issues (this app is personal/local — traditional web security does not apply).

| Mistake | Risk | Prevention |
|---------|------|------------|
| Enabling App Sandbox without correct entitlements | App silently cannot read `~/.claude/`; may try to request user consent via file dialog, leaking UX friction | Disable sandbox entirely (personal use, no App Store); document the decision in entitlements file |
| Writing parsed token data to disk (caching) | Creates a secondary copy of potentially sensitive project path data | Keep all state in memory only; re-derive from JSONL on launch — files are small enough |
| Logging JSONL content to system Console for debug | Project names and file paths in `~/.claude/projects/` are exposed to any app with Console access | Use `os.log` at `.debug` level only, redact file paths in release builds |

---

## UX Pitfalls

Common user experience mistakes specific to macOS menu bar token trackers.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing raw token numbers only (e.g. "38,291 / 44,000") | Users cannot quickly assess how close to limit they are — requires mental math | Lead with percentage or progress bar; show number as secondary info |
| Not showing reset time | Users do not know if the limit will reset in 5 minutes or 3 hours | Always show "resets in Xh Ym" alongside current usage |
| Progress bar exceeds 100% (no clamping) | Progress bar overflows its container visually | Clamp progress value to `[0.0, 1.0]` regardless of calculated usage |
| Updating the status bar label every second with a countdown timer | Causes constant re-render of the status item; contributes to CPU usage; distracts users while typing | Update the status bar label at most every 60 seconds; update the dropdown on open only |
| "Looks inactive" when usage is 0% | Users cannot tell if the app is running or crashed | Show "0 tokens used" or an empty-but-visible progress bar, not a blank icon |

---

## "Looks Done But Isn't" Checklist

Things that appear complete in basic testing but are missing critical pieces.

- [ ] **File reading:** Test with a JSONL file that has a blank line mid-file — blank lines will cause `JSONDecoder` to throw; verify the parser skips them gracefully
- [ ] **Token window:** Test with log entries that span exactly the 4-hour boundary — verify entries at `now - 4h - 1s` are excluded and `now - 4h + 1s` are included
- [ ] **Menu bar icon:** Test on a machine with a light-colored desktop wallpaper where the menu bar is light — verify the icon is visible (not black-on-white invisible)
- [ ] **Sandbox:** Archive the app and inspect the `.entitlements` file in the archive — verify `com.apple.security.app-sandbox` is `false` or the correct home-directory entitlement is present
- [ ] **Login item:** After enabling "Launch at Login" and rebooting, verify the app actually launches — SMAppService registration can silently fail on first attempt
- [ ] **Large files:** Create a synthetic JSONL file with 50,000 entries; verify the app does not hang on launch while reading initial state
- [ ] **Multiple projects:** Verify token counts aggregate correctly across all `~/.claude/projects/*/` subdirectories, not just the first one found
- [ ] **Cache tokens:** Verify `cache_creation_input_tokens` and `cache_read_input_tokens` are included in the usage total — easy to accidentally sum only `input_tokens + output_tokens`

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Shipped with `.window` style MenuBarExtra, needs native feel | HIGH | Rewrite popup as `NSMenu + NSHostingView`; data model is unaffected; UI layer is replaced |
| Sandbox blocks file access in a distributed build | MEDIUM | Add `com.apple.security.temporary-exception.files.home-relative-path.read-only` for `/.claude/`; re-sign; re-distribute |
| Main thread file reads cause stutters | MEDIUM | Wrap reads in `Task { }`, add `@MainActor` dispatch for state update; incremental read requires adding offset tracking |
| Wrong timezone in window calculation | LOW | Fix `ISO8601DateFormatter` usage; remove `Calendar.current` from window math; no data model changes |
| Template image issue (icon invisible in some modes) | LOW | Load image, set `isTemplate = true`, reassign to status button — one-line fix |
| Dock icon flash on launch | LOW | Add `LSUIElement = YES` to `Info.plist`; remove `setActivationPolicy` call from `AppDelegate` |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Wrong MenuBarExtra style | Phase 1 — Core scaffold | Popup opens with native feel; progress bar renders correctly in dropdown |
| Sandbox blocks `~/.claude/` reads | Phase 1 — Core scaffold | Entitlements file reviewed; JSONL read succeeds in a non-debug scheme |
| Full-file re-reads | Phase 2 — File reading & aggregation | FileHandle offset tracking exists; CPU stays < 1% during idle polling |
| Timezone/window calculation errors | Phase 2 — Token aggregation logic | Unit tests pass for entries spanning UTC midnight across multiple timezones |
| Dock icon flash | Phase 1 — Core scaffold | `LSUIElement = YES` in `Info.plist`; no Dock icon visible at any point during launch |
| Stale counts when menu opens | Phase 3 — UI wiring & refresh | NSMenu delegate `menuWillOpen` triggers re-aggregate; counts reflect reality at open time |
| Non-template status bar icon | Phase 3 — UI polish | Icon visible in both light and dark menu bar appearances |
| Cache token omission | Phase 2 — Token aggregation logic | Unit test asserts sum includes all four token fields |
| Hardcoded token limits | Phase 2 — Config | Limits read from a config source, not embedded as magic numbers |
| SMAppService login item state | Phase 4 — Login item feature | Toggle reflects SMAppService.status, not UserDefaults; survives System Settings override |

---

## Sources

- [Showing Settings from macOS Menu Bar Items: A 5-Hour Journey — Peter Steinberger](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — settings window activation policy complexity
- [What I Learned Building a Native macOS Menu Bar App — DEV Community](https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6) — NSPopover vs NSMenu post-mortem, sandbox restrictions, hybrid 70/30 pattern
- [MenuBarExtraAccess — orchetect/MenuBarExtraAccess on GitHub](https://github.com/orchetect/MenuBarExtraAccess) — workarounds for MenuBarExtra presentation state limitations
- [FB13683950: MenuBarExtra (.menu style) needs open event — feedback-assistant/reports](https://github.com/feedback-assistant/reports/issues/475) — confirmed missing open callback
- [FB11984872: MenuBarExtra (.window style) needs programmatic close — feedback-assistant/reports](https://github.com/feedback-assistant/reports/issues/383) — confirmed missing close API
- [Accessing files from the macOS App Sandbox — Apple Developer Documentation](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — sandbox home directory behavior
- [App Sandbox Temporary Exception Entitlements — Apple Documentation Archive](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) — home-relative-path entitlement
- [Reading large files fast and memory efficient — Swift Forums](https://forums.swift.org/t/reading-large-files-fast-and-memory-efficient/37704) — FileHandle incremental reads in Swift
- [The Mac Menubar and SwiftUI — TrozWare (2025)](https://troz.net/post/2025/mac_menu_data/) — SwiftUI/AppKit communication in menu bar context
- [Build a macOS menu bar utility in SwiftUI — nilcoalescing.com](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MenuBarExtra pattern reference
- [Add launch at login setting to a macOS app — nilcoalescing.com](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — SMAppService correct usage
- [Using the MainActor attribute — Swift by Sundell](https://www.swiftbysundell.com/articles/the-main-actor-attribute/) — background thread / main actor threading model
- [Designing macOS menu bar extras — bjango.com](https://bjango.com/articles/designingmenubarextras/) — template image design requirements

---
*Pitfalls research for: native macOS menu bar token tracker (SwiftUI/AppKit, JSONL file reading, time-windowed progress bars)*
*Researched: 2026-03-11*
