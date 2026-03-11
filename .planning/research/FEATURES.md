# Feature Research

**Domain:** macOS menu bar developer utility — Claude Code token usage tracker
**Researched:** 2026-03-11
**Confidence:** HIGH (multiple competing apps exist, conventions well-established)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in any menu bar usage monitor. Missing these = product feels incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Menu bar icon showing current usage | Core purpose of the app; if the icon doesn't tell you at a glance, why install it | LOW | Progress bar or percentage in icon; template image required for light/dark adaptation |
| Popover/panel on click showing detail | Every menu bar utility opens a panel; this is the universal pattern | LOW | Use NSMenu or MenuBarExtra popover; NSMenu feels more native than NSPopover |
| 4-hour window progress bar + stats | The reset window is the metric users care about most; it's what they're racing against | LOW | Show used, remaining, reset time |
| Weekly window progress bar + stats | Secondary limit that matters for heavy users | LOW | Same layout as 4-hour window |
| Auto-refresh of data | Stale data is worse than no data; users expect live stats | LOW | File polling every 30–60s is sufficient; log files don't update every second |
| Launch at login toggle | Every persistent menu bar utility offers this; absence feels unfinished | LOW | Use SMAppService on macOS 13+; present as checkbox in settings |
| No Dock icon | Menu bar utilities must not appear in Dock; violates macOS convention | LOW | Set `LSUIElement = true` in Info.plist |
| Quit option | Users must be able to exit; right-click or menu item is mandatory | LOW | Right-click menu item "Quit" or item in popover footer |
| Readable token counts | Raw numbers like "48392" are hard to parse; formatting matters | LOW | Format as "48.4K tokens" or "48,392"; rounding is fine |
| Reset countdown timer | Users need to know when the window resets, not just how much is left | LOW | "Resets in 1h 23m" next to each progress bar |
| Light/dark mode icon adaptation | macOS menu bar icons must adapt; a white icon on a white menu bar is invisible | LOW | Use SF Symbols or template image rendering |

### Differentiators (Competitive Advantage)

Features that go beyond what competitors have or do significantly better. This app's differentiator should be **simplicity and zero-config** — competitors like Claude-Usage-Tracker (hamed-elfayome) are feature-heavy with multi-profile management, API console integration, terminal statuslines, 9-language support, and browser-based auth. This project's edge is being the tool that "just works" from local files alone.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Threshold notification at configurable % | Proactively warns before hitting limit mid-session; most-cited pain point is surprise cutoffs | MEDIUM | Use UserNotifications framework; sensible defaults (80%, 95%) with override in settings |
| Pace indicator (on-track / at-risk) | Tells users whether current burn rate will exhaust the window before reset; transforms data from descriptive to actionable | MEDIUM | Compute tokens-per-hour from log history, project forward to reset time; green/yellow/red |
| Per-session breakdown (today's sessions) | Shows how this window's usage is distributed across time; helps users understand their own patterns | MEDIUM | Group log entries by contiguous work sessions (gap > 30 min = new session) |
| Cache token visibility | Claude Code's caching reduces effective token cost significantly; showing cache hit rates gives users insight into actual cost | LOW | Already in log data: cache_creation_input_tokens + cache_read_input_tokens |
| FSEvents file watcher (vs. polling) | More responsive and lower CPU than polling; data updates the moment Claude Code writes to log | MEDIUM | NSFilePresenter or FSEventStreamCreate; fall back to polling if needed |
| Clean minimal UI, zero config | Competitors require auth flows, profile setup, API keys; this app reads local files and works immediately on first launch | LOW | No setup wizard, no accounts, no network calls |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Claude.ai web usage tracking | Users want a single pane for all Claude usage | No public API; requires browser auth, cookie scraping, fragile session tokens; breaks on any Claude.ai change | Explicitly out of scope per PROJECT.md; document why in the UI if asked |
| Anthropic API billing / cost tracking | Cost is real money; developers want to track spend | Claude Code usage logs contain token counts but no pricing data; prices change; requires Anthropic API key and separate endpoint; different product from rate limits | Out of scope; direct users to Anthropic console for billing |
| Multi-account / profile switching | Teams share machines; some users have multiple accounts | Adds significant complexity (credential storage, Keychain, profile switching); Claude Code itself manages auth; this app only reads files | The logged-in user's `~/.claude/projects/` is always the correct scope |
| Historical usage charts / analytics | "I want to see my weekly trend" | Requires persistent storage, migrations, charting library; heavy scope creep for a utility that answers "where am I right now?" | Show a simple "this week" summary using existing log data without a separate database |
| Settings window (full preferences pane) | Expected by power users | A full preferences window is disproportionate for a 3-setting app; creates UI debt | Use a compact in-popover settings section (toggle launch at login, set notification threshold) |
| Automatic updates (Sparkle) | Convenience | Sparkle adds a dependency and distribution overhead; this is a personal tool, not a distributed product | GitHub releases + manual download; or document how to build from source |
| Menubar icon with full text label | Want to see exact number without clicking | Long text labels shift other menu bar icons, cause truncation at smaller widths, conflict with system items | Use icon + compact number (e.g. progress bar + "74%"); keep it short |
| Windows/Linux support | Some users want cross-platform | Explicitly out of scope; NSStatusBar is macOS-only; the data format is the same but the surface is completely different | Not addressed; macOS only |

## Feature Dependencies

```
[Menu bar icon with usage]
    └──requires──> [JSONL log parser]
                       └──requires──> [~/.claude/projects/ file reader]

[Popover panel]
    └──requires──> [Menu bar icon with usage]
    └──requires──> [JSONL log parser]

[4-hour window progress bar]
    └──requires──> [JSONL log parser]
    └──requires──> [Reset window calculator (timestamp math)]

[Weekly window progress bar]
    └──requires──> [JSONL log parser]
    └──requires──> [Reset window calculator]

[Threshold notification]
    └──requires──> [4-hour window progress bar]
    └──requires──> [UserNotifications permission]

[Pace indicator]
    └──requires──> [JSONL log parser]
    └──requires──> [Reset window calculator]
    └──enhances──> [4-hour window progress bar]

[Auto-refresh / file watcher]
    └──enhances──> [All display features]
    └──requires──> [JSONL log parser]

[Cache token visibility]
    └──requires──> [JSONL log parser]
    └──enhances──> [Popover panel detail view]

[Launch at login]
    └──requires──> [SMAppService (macOS 13+)]
    └──independent of──> [all data features]
```

### Dependency Notes

- **JSONL log parser is the foundation**: Every data-bearing feature depends on correctly reading and aggregating `~/.claude/projects/**/*.jsonl`. Get this right first.
- **Reset window calculator is critical**: Both the 4-hour and weekly windows require knowing the exact reset moment. The 4-hour window rolls from the first token use in a block; this is not a fixed clock time. Verify the reset logic against real log data.
- **Threshold notification requires permission**: UserNotifications authorization must be requested at first run. If the user denies, degrade gracefully (no crash, surface a "Notifications disabled" hint in settings).
- **Pace indicator enhances but doesn't gate**: It can be added after the core display works; it reads the same data but adds projection logic.
- **Launch at login is fully independent**: It can be wired up at any phase; it touches no data layer.

## MVP Definition

### Launch With (v1)

Minimum to validate the concept. Every item here is something that, if missing, makes the app not worth using.

- [ ] Menu bar icon with compact usage indicator (progress bar or percentage) — the app's entire reason for existing
- [ ] Left-click opens popover showing both windows (4-hour + weekly) with used/remaining/reset time — the detail view
- [ ] JSONL log parser reading all token types (input, output, cache creation, cache read) from `~/.claude/projects/**/*.jsonl` — the data foundation
- [ ] Reset window calculator that correctly computes the 4-hour rolling window and weekly reset — without this, numbers are wrong
- [ ] Auto-refresh via polling (30–60 second interval) — stale data breaks trust
- [ ] No Dock icon, light/dark icon adaptation — mandatory macOS convention compliance
- [ ] Quit menu item — users must be able to exit

### Add After Validation (v1.x)

Add once the core is working and used daily.

- [ ] Threshold notification at configurable % — add when users express the "surprised by limit" pain point (or when you feel it yourself)
- [ ] Launch at login toggle — add when you want the app to survive reboots
- [ ] Pace indicator (on-track / at-risk) — add when the basic display feels complete but not actionable enough
- [ ] Cache token visibility in detail view — low effort, surfaces useful data already in logs

### Future Consideration (v2+)

Defer until v1 is stable and used long enough to know if these matter.

- [ ] FSEvents file watcher — only matters if polling latency is felt; polling at 30s is fine for this use case
- [ ] Per-session breakdown — useful for understanding patterns but adds display complexity
- [ ] In-popover settings section — only needed if there are settings to surface

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Menu bar icon with usage | HIGH | LOW | P1 |
| Popover with 4-hour + weekly windows | HIGH | LOW | P1 |
| JSONL log parser (all token types) | HIGH | LOW | P1 |
| Reset window calculator | HIGH | MEDIUM | P1 |
| Auto-refresh (polling) | HIGH | LOW | P1 |
| No Dock icon + icon adaptation | HIGH | LOW | P1 |
| Quit menu item | HIGH | LOW | P1 |
| Threshold notification | HIGH | MEDIUM | P2 |
| Launch at login toggle | MEDIUM | LOW | P2 |
| Pace indicator | MEDIUM | MEDIUM | P2 |
| Cache token visibility | MEDIUM | LOW | P2 |
| FSEvents file watcher | LOW | MEDIUM | P3 |
| Per-session breakdown | LOW | MEDIUM | P3 |
| In-popover settings | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

The competitive landscape reveals a spectrum from "minimal shell script + xbar" to "full-featured commercial app." This project sits in the middle: native Swift, zero config, local-only.

| Feature | Claude-Usage-Tracker (hamed-elfayome) | ClaudeBar (tddworks) | masorange/ClaudeUsageTracker | Our Approach |
|---------|---------------------------------------|----------------------|------------------------------|--------------|
| Data source | Claude.ai session API (browser auth) | Claude.ai session API | LiteLLM API | Local JSONL files only — zero auth, zero network |
| 4-hour / 5-hour window | Yes | Yes | No (cost-focused) | Yes |
| Weekly window | Yes | Yes | Monthly cost | Yes |
| Menu bar icon | Progress bar, battery, percentage — 5 styles | Color-coded bar | Cost number | Simple bar + number |
| Notifications | Yes, threshold + sound picker | Yes, warning/critical | No | Yes, configurable % |
| Pace indicator | Yes, 6-tier system | No | No | Yes, simplified (on-track / at-risk) |
| Multi-account | Yes, unlimited profiles | No | No | No — local files = single account |
| Settings complexity | High (sidebar, profiles, API keys) | Medium | Low | Low — in-popover or minimal window |
| Distribution | Signed .app | Open source | Homebrew | Local build |
| Authentication required | Yes (Claude.ai session key or CLI token) | Yes | Yes (LiteLLM API) | No — reads files directly |

**Key differentiator insight:** Every competitor that uses Claude's API endpoints requires authentication and is exposed to API changes. Reading `~/.claude/projects/**/*.jsonl` locally is simpler, more robust, and requires no credentials. This is the right bet for a personal tool.

## Sources

- [GitHub: hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker) — most feature-complete competitor; good baseline for what "complete" looks like
- [GitHub: masorange/ClaudeUsageTracker](https://github.com/masorange/ClaudeUsageTracker) — cost-focused variant; LiteLLM API approach
- [GitHub: tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) — multi-provider approach; shows what scope creep looks like
- [DEV Community: I got tired of hitting AI rate limits mid-task](https://dev.to/jamie_b714bfb128f0fd9ce03/i-got-tired-of-hitting-ai-rate-limits-mid-task-so-i-built-a-macos-menu-bar-monitor-for-it-eng) — articulates the core user pain point clearly; validates pace indicator value
- [Preslav Rachev: Claude Code token usage on macOS toolbar](https://preslav.me/2025/08/04/put-claude-code-token-usage-macos-toolbar/) — confirms the JSONL file approach is viable from the community
- [DEV Community: What I Learned Building a Native macOS Menu Bar App](https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6) — NSMenu vs NSPopover, hybrid AppKit/SwiftUI, LSUIElement conventions
- [Apple Developer Documentation: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) — authoritative reference for status item behavior

---
*Feature research for: macOS menu bar Claude Code token usage tracker*
*Researched: 2026-03-11*
