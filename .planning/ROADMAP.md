# Roadmap: Claude Usage

## Overview

Four phases build the app bottom-up: scaffold the correct macOS app structure first (getting the hard architectural decisions right before writing any business logic), then build and test the data layer in isolation, then wire data to a complete live UI, and finally add the login persistence feature. Each phase delivers something independently verifiable.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Scaffold** - Running macOS app in the menu bar with correct entitlements and no Dock icon
- [ ] **Phase 2: Data Layer** - Tested JSONL parser and token aggregator with correct rolling window math
- [ ] **Phase 3: Live Display** - Full UI wired to real data with auto-refresh
- [ ] **Phase 4: Login Persistence** - Launch-at-login toggle that survives reboots

## Phase Details

### Phase 1: Scaffold
**Goal**: A running macOS app exists in the menu bar with the correct architectural foundation — right MenuBarExtra style, App Sandbox disabled, no Dock icon — before any business logic is written
**Depends on**: Nothing (first phase)
**Requirements**: MBAR-01, DISP-05
**Success Criteria** (what must be TRUE):
  1. Building and running the app shows a menu bar icon with no Dock icon and no app in the App Switcher
  2. Clicking the menu bar icon opens a popover/panel (even if empty)
  3. A "Quit" item in the panel exits the app cleanly
  4. App Sandbox is disabled and an archive build can read files from the home directory without silent failure
**Plans**: TBD

### Phase 2: Data Layer
**Goal**: A fully tested data layer correctly reads all JSONL token fields from ~/.claude/projects/, computes the 4-hour rolling window with timezone-safe math, and aggregates totals — all running on a background thread
**Depends on**: Phase 1
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04
**Success Criteria** (what must be TRUE):
  1. Parser reads all four token fields (input, output, cache_creation, cache_read) and skips malformed lines without crashing
  2. The 4-hour window correctly includes/excludes entries at the UTC midnight boundary (verified by unit tests with fixture files)
  3. Token counts in the app match a manual count of the JSONL files for the same time window
  4. Token data refreshes automatically every 30-60 seconds without blocking the UI
**Plans**: TBD

### Phase 3: Live Display
**Goal**: Users can see live 4-hour and weekly token usage — progress bars, counts, reset times — directly in the menu bar and dropdown, with a burn-rate warning when on track to exhaust the window
**Depends on**: Phase 2
**Requirements**: MBAR-02, MBAR-03, MBAR-04, DISP-01, DISP-02, DISP-03, DISP-04
**Success Criteria** (what must be TRUE):
  1. Menu bar shows a mini progress bar and remaining token count at all times without opening anything
  2. Clicking the menu bar item opens a dropdown showing both the 4-hour window and weekly window, each with a progress bar, tokens used, tokens remaining, and reset time
  3. The last refresh timestamp is visible in the dropdown
  4. Menu bar icon or progress bar changes appearance (color or style) when current burn rate risks exhausting the 4-hour window before reset
**Plans**: TBD

### Phase 4: Login Persistence
**Goal**: The app survives a reboot — users can enable launch at login from the dropdown and the setting persists
**Depends on**: Phase 3
**Requirements**: SYS-01
**Success Criteria** (what must be TRUE):
  1. The dropdown contains a toggle for "Launch at Login"
  2. Enabling the toggle, quitting the app, and rebooting the machine results in the app appearing in the menu bar automatically at login
  3. Disabling the toggle and rebooting results in the app not launching
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Scaffold | 0/TBD | Not started | - |
| 2. Data Layer | 0/TBD | Not started | - |
| 3. Live Display | 0/TBD | Not started | - |
| 4. Login Persistence | 0/TBD | Not started | - |
