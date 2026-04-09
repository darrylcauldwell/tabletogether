#!/usr/bin/env bash
# TableTogether Preflight Validation
# Run before pushing to catch issues locally in seconds.
#
# Usage:
#   scripts/preflight.sh          # Full validation
#   scripts/preflight.sh --quick  # Skip tests and builds
set -euo pipefail

QUICK=false
FAIL=0
STAGE=0

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=true ;;
  esac
done

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAIL=1; }
stage() { STAGE=$((STAGE + 1)); echo ""; echo "=== Stage $STAGE: $1 ==="; }

# Ensure we're in the repo root
cd "$(git rev-parse --show-toplevel)"

# --- Stage 0: SwiftLint ---
stage "SwiftLint"

if command -v swiftlint > /dev/null 2>&1; then
  if swiftlint --quiet 2>&1 | tee /tmp/swiftlint.log | grep -q "error:"; then
    fail "SwiftLint found errors"
  else
    pass "SwiftLint passed (warnings allowed)"
  fi
else
  pass "SwiftLint not installed — skipping (brew install swiftlint)"
fi

# --- Stage 1: Version Consistency ---
stage "Version Consistency"

IOS_VERSION=$(grep "MARKETING_VERSION" project.yml | head -1 | sed 's/.*: *//' | tr -d '"')
if [ -n "$IOS_VERSION" ]; then
  pass "iOS MARKETING_VERSION = $IOS_VERSION (from project.yml)"
else
  fail "Could not read MARKETING_VERSION from project.yml"
fi

TV_VERSIONS=$(grep "MARKETING_VERSION" TableTogetherTV/TableTogetherTV.xcodeproj/project.pbxproj 2>/dev/null | sed 's/.*= //' | sed 's/;.*//' | sort -u)
TV_COUNT=$(echo "$TV_VERSIONS" | wc -l | tr -d ' ')
if [ "$TV_COUNT" -le 1 ]; then
  pass "tvOS MARKETING_VERSION = $(echo "$TV_VERSIONS" | tr -d ' ')"
else
  fail "Multiple tvOS MARKETING_VERSION values: $TV_VERSIONS"
fi

# --- Stage 2: Metadata Limits ---
stage "Metadata Limits"

if [ -x scripts/validate_metadata.sh ]; then
  if scripts/validate_metadata.sh > /dev/null 2>&1; then
    pass "All metadata within character limits"
  else
    fail "Metadata character limits exceeded"
  fi
else
  pass "validate_metadata.sh not found — skipping"
fi

# --- Stage 3: XcodeGen Project Generation ---
stage "Project Generation"

if command -v xcodegen > /dev/null 2>&1; then
  if xcodegen generate --spec project.yml > /dev/null 2>&1; then
    pass "XcodeGen project generated successfully"
  else
    fail "XcodeGen project generation failed"
  fi
else
  fail "XcodeGen not installed (brew install xcodegen)"
fi

# --- Stage 4: Core Data Model Change Detection ---
stage "CloudKit Schema Check"

XCDATAMODELD_PATH="TableTogether/Sources/CoreData/TableTogether.xcdatamodeld"
MODEL_CHANGES=$(git diff --cached --name-only -- "$XCDATAMODELD_PATH" 2>/dev/null || true)
if [ -z "$MODEL_CHANGES" ]; then
  # Also check unstaged/untracked changes (catch before staging)
  MODEL_CHANGES=$(git diff --name-only -- "$XCDATAMODELD_PATH" 2>/dev/null || true)
fi

if [ -n "$MODEL_CHANGES" ]; then
  echo ""
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║  ⚠️  CORE DATA MODEL CHANGED — CloudKit schema deploy needed   ║"
  echo "  ╠══════════════════════════════════════════════════════════════════╣"
  echo "  ║                                                                  ║"
  echo "  ║  Changed files:                                                  ║"
  for f in $MODEL_CHANGES; do
    printf "  ║    %-60s ║\n" "$f"
  done
  echo "  ║                                                                  ║"
  echo "  ║  Before shipping to TestFlight you MUST:                         ║"
  echo "  ║    1. Run a Debug build to push schema to CloudKit Development   ║"
  echo "  ║    2. Open the CloudKit Dashboard and deploy Dev → Production    ║"
  echo "  ║                                                                  ║"
  echo "  ║  Dashboard: https://icloud.developer.apple.com/dashboard/        ║"
  echo "  ║  Container: iCloud.com.darrylcauldwell.tabletogether             ║"
  echo "  ║                                                                  ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo ""

  # Escalate if new entities or attributes were added
  NEW_SCHEMA=$(git diff --cached --unified=0 -- "$XCDATAMODELD_PATH" 2>/dev/null | grep "^+" | grep -E '<(entity|attribute) ' || true)
  if [ -z "$NEW_SCHEMA" ]; then
    NEW_SCHEMA=$(git diff --unified=0 -- "$XCDATAMODELD_PATH" 2>/dev/null | grep "^+" | grep -E '<(entity|attribute) ' || true)
  fi

  if [ -n "$NEW_SCHEMA" ]; then
    echo "  New entities/attributes detected:"
    echo "$NEW_SCHEMA" | sed 's/^+/    /'
    echo ""
    if [ -t 0 ]; then
      read -rp "  Schema deploy is REQUIRED for these changes. Continue? [y/N] " REPLY
      if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "  Aborting — deploy schema first."
        exit 1
      fi
    else
      echo "  [WARN] Non-interactive mode — cannot prompt. Deploy schema before TestFlight!"
    fi
  fi

  pass "CloudKit schema warning displayed"
else
  pass "No Core Data model changes detected"
fi

if $QUICK; then
  echo ""
  echo "=== Quick mode — skipping builds and tests ==="
  echo ""
  if [ "$FAIL" -ne 0 ]; then
    echo "PREFLIGHT FAILED"
    exit 1
  fi
  echo "PREFLIGHT PASSED (quick)"
  exit 0
fi

# --- Stage 5: Build Verification ---
stage "Build Verification (iOS Simulator)"

if xcodebuild build \
  -project TableTogether.xcodeproj \
  -scheme TableTogether \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet 2>&1 | grep -q "error:"; then
  fail "iOS build failed"
else
  pass "iOS Simulator build succeeded"
fi

stage "Build Verification (Mac Catalyst)"

if xcodebuild build \
  -project TableTogether.xcodeproj \
  -scheme TableTogether \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet 2>&1 | grep -q "error:"; then
  fail "Mac Catalyst build failed"
else
  pass "Mac Catalyst build succeeded"
fi

stage "Build Verification (tvOS Simulator)"

if xcodebuild build \
  -project TableTogetherTV/TableTogetherTV.xcodeproj \
  -scheme TableTogetherTV \
  -destination 'generic/platform=tvOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet 2>&1 | grep -q "error:"; then
  fail "tvOS build failed"
else
  pass "tvOS Simulator build succeeded"
fi

stage "Unit Tests"

# Find a booted iPhone simulator, or fall back to any available iPhone.
# Each pipeline ends with `|| true` so `set -euo pipefail` doesn't abort the
# script when grep finds nothing (no booted sim is a valid state we want to
# handle via the fallback, not a fatal error).
SIM_ID=$(xcrun simctl list devices booted | grep "iPhone" | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()' | head -1 || true)
if [ -z "$SIM_ID" ]; then
  SIM_ID=$(xcrun simctl list devices available | grep "iPhone" | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()' | head -1 || true)
fi

if [ -n "$SIM_ID" ]; then
  if xcodebuild test \
    -project TableTogether.xcodeproj \
    -scheme TableTogether \
    -destination "id=$SIM_ID" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    -quiet 2>&1 | grep -q "TEST FAILED"; then
    fail "Unit tests failed"
  else
    pass "Unit tests passed"
  fi
else
  pass "No iOS simulator available — skipping tests"
fi

# --- Summary ---
echo ""
echo "==============================="
if [ "$FAIL" -ne 0 ]; then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT PASSED"
exit 0
