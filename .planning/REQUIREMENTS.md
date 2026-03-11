# Requirements: Claude Usage

**Defined:** 2026-03-11
**Core Value:** At a glance, from the menu bar: know exactly where you stand in your current token window before you hit the limit.

## v1 Requirements

### Menu Bar

- [ ] **MBAR-01**: App icon always visible in macOS menu bar with no Dock icon (LSUIElement = YES in Info.plist)
- [ ] **MBAR-02**: Menu bar displays a mini progress bar showing 4-hour window usage at all times
- [ ] **MBAR-03**: Menu bar displays remaining token count next to the progress bar
- [ ] **MBAR-04**: Menu bar icon/bar changes appearance (color or style) when current burn rate risks exhausting the 4-hour window before reset

### Usage Display

- [ ] **DISP-01**: Clicking the menu bar item opens a dropdown panel
- [ ] **DISP-02**: Dropdown shows 4-hour rolling window with: progress bar, tokens used, tokens remaining, time until reset
- [ ] **DISP-03**: Dropdown shows weekly window with: progress bar, tokens used, tokens remaining, date/time of reset
- [ ] **DISP-04**: Dropdown shows last refresh timestamp
- [ ] **DISP-05**: Dropdown includes a Quit menu item

### Data

- [ ] **DATA-01**: App reads all files matching ~/.claude/projects/**/*.jsonl
- [ ] **DATA-02**: Parser extracts input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens, and timestamp from each log entry (skips undecodable lines)
- [ ] **DATA-03**: 4-hour window is a rolling window computed from current UTC time minus 4 hours (not a fixed clock interval)
- [ ] **DATA-04**: App auto-refreshes token data on a 30–60 second timer

### System

- [ ] **SYS-01**: App offers a toggle in the dropdown to enable/disable launch at macOS login (via SMAppService)

## v2 Requirements

### Data Detail

- **DATA-05**: Show cache_creation and cache_read token counts separately in the dropdown
- **DATA-06**: Show per-session token breakdown (grouped by Claude Code session)

### Notifications

- **NOTF-01**: Send macOS notification when 4-hour window usage crosses a configurable threshold (default 80%)

### Refresh

- **REFR-01**: Use FSEvents/kqueue file watcher for near-instant refresh instead of polling timer

## Out of Scope

| Feature | Reason |
|---------|--------|
| Claude.ai web usage tracking | No public API; different client from Claude Code |
| Anthropic API billing usage | Separate system from Claude Code rate limits |
| Windows/Linux support | macOS menu bar only; NSStatusBar/MenuBarExtra are macOS-specific |
| Manual token entry | Data is always sourced from local logs |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MBAR-01 | Phase 1 | Pending |
| MBAR-02 | Phase 3 | Pending |
| MBAR-03 | Phase 3 | Pending |
| MBAR-04 | Phase 3 | Pending |
| DISP-01 | Phase 3 | Pending |
| DISP-02 | Phase 3 | Pending |
| DISP-03 | Phase 3 | Pending |
| DISP-04 | Phase 3 | Pending |
| DISP-05 | Phase 1 | Pending |
| DATA-01 | Phase 2 | Pending |
| DATA-02 | Phase 2 | Pending |
| DATA-03 | Phase 2 | Pending |
| DATA-04 | Phase 2 | Pending |
| SYS-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after roadmap creation*
