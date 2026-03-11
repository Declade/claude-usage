#!/usr/bin/env bash
set -euo pipefail

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "ClaudeUsage.app" -path "*/Debug/*" 2>/dev/null | head -1)

if [[ -z "$APP" ]]; then
    echo "Build not found. Run: xcodebuild build -scheme ClaudeUsage -destination 'platform=macOS'"
    exit 1
fi

echo "Checking: $APP"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Check 1 — LSUIElement
echo "Check 1: LSUIElement"
LSUIELEMENT=$(defaults read "$APP/Contents/Info.plist" LSUIElement 2>/dev/null || echo "MISSING")
if [[ "$LSUIELEMENT" == "1" ]]; then
    echo "  PASS — LSUIElement = $LSUIELEMENT"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL — LSUIElement = $LSUIELEMENT (expected: 1)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check 2 — Sandbox disabled
echo "Check 2: App Sandbox disabled"
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>&1)
if echo "$ENTITLEMENTS" | grep -q "com.apple.security.app-sandbox.*true"; then
    echo "  FAIL — com.apple.security.app-sandbox is set to true"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo "  PASS — com.apple.security.app-sandbox is absent or false"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

echo ""
echo "${PASS_COUNT}/2 checks passed"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi

exit 0
