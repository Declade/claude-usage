# Claude Usage

## What This Is

A native macOS menu bar app (Swift/SwiftUI) that shows Claude Code token usage in real time. It reads usage logs from `~/.claude/projects/` and displays progress bars for the current 4-hour reset window and the weekly reset, so you always know how much you've used and how much you have left — right from the top bar.

## Core Value

At a glance, from the menu bar: know exactly where you stand in your current token window before you hit the limit.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] App lives in the macOS menu bar (no Dock icon)
- [ ] Menu bar shows a mini progress bar + remaining token count at all times
- [ ] Clicking the menu bar item opens a dropdown panel
- [ ] Dropdown shows two progress bars: 4-hour window and weekly window
- [ ] Dropdown shows tokens used, tokens remaining, and reset time for each window
- [ ] Token data is read from ~/.claude/projects/**/*.jsonl (input_tokens + output_tokens + cache tokens)
- [ ] Data refreshes automatically (polling or file watcher)
- [ ] App launches at login (optional toggle)

### Out of Scope

- Claude.ai web usage tracking — no public API available; different client
- Anthropic API billing usage — separate from Claude Code rate limits
- Windows/Linux support — macOS menu bar only
- Manual token entry — data is always from local logs

## Context

- Claude Code logs every API call to `~/.claude/projects/**/*.jsonl` with exact token counts and ISO timestamps
- Relevant fields per log entry: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `timestamp`
- The 4-hour reset window and weekly reset window are Claude Code plan rate limits
- Building as a native Swift/SwiftUI app for best macOS integration and minimal resource usage
- App needs file system read access to ~/.claude/ — no special entitlements needed for sandboxed reads of home directory files

## Constraints

- **Platform**: macOS only — leverages NSStatusBar / SwiftUI MenuBarExtra
- **Data access**: Read-only access to ~/.claude/projects/ — no writes, no network calls
- **Distribution**: Local build / personal use — no App Store submission required

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift/SwiftUI over Electron | Native feel, minimal memory footprint, best menu bar support | — Pending |
| Read local JSONL files | Only accurate data source for Claude Code usage; no API available for Claude.ai | — Pending |
| File polling (vs FSEvents) | Simpler to implement; usage logs update infrequently | — Pending |

---
*Last updated: 2026-03-11 after initialization*
