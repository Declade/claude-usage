---
phase: 1
slug: scaffold
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in Xcode) + manual shell verification |
| **Config file** | none — defined via XcodeGen `project.yml` test target |
| **Quick run command** | `xcodebuild build -scheme ClaudeUsage -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -scheme ClaudeUsage -destination 'platform=macOS'` |
| **Estimated runtime** | ~30 seconds (build-only check) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme ClaudeUsage -destination 'platform=macOS'`
- **After every plan wave:** Manual smoke test checklist (4 items below) + `scripts/verify-scaffold.sh`
- **Before `/gsd:verify-work`:** All 4 verification items must be green
- **Max feedback latency:** ~30 seconds (build check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| MBAR-01 LSUIElement | 01 | 1 | MBAR-01 | Shell | `defaults read .../Info.plist LSUIElement` → 1 | ❌ Wave 0 | ⬜ pending |
| MBAR-01 No Dock | 01 | 1 | MBAR-01 | Manual smoke | Launch app, verify no Dock icon | ❌ Wave 0 | ⬜ pending |
| DISP-05 Quit | 01 | 1 | DISP-05 | Manual smoke | Click Quit, verify process exits | ❌ Wave 0 | ⬜ pending |
| Sandbox | 01 | 1 | MBAR-01 | Shell | `codesign -d --entitlements` shows sandbox absent | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `ClaudeUsageTests/PlaceholderTests.swift` — empty test file to satisfy test target linkage
- [ ] `scripts/verify-scaffold.sh` — shell script automating LSUIElement + entitlements checks

*Note: Phase 1 requirements are structural/configuration properties of the built app bundle, not logic. They cannot be unit-tested with XCTest. Validation is manual smoke test + shell verification commands.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No Dock icon when app is running | MBAR-01 | Bundle property, not testable with XCTest | Launch app in Simulator or on device; confirm no icon in Dock |
| Clicking menu bar icon opens panel | DISP-05 | UI interaction | Launch app; click menu bar icon; confirm panel appears |
| Quit exits app cleanly | DISP-05 | Process lifecycle | Open panel; click Quit; confirm app exits (no zombie process) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
