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

# Run a build/test command and report pass/fail by its REAL exit status.
# Redirecting to a log (instead of `if cmd | grep -q error:`) is deliberate:
# under `set -o pipefail` the old form reported PASS on genuine failures, because
# the failed command's non-zero exit propagated through the pipe and sent the
# `if` down the else/PASS branch — silently defeating the whole validation gate.
# Args: <label> <logfile> <command...>
run_checked() {
  local label="$1"; shift
  local log="$1"; shift
  set +e
  "$@" > "$log" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    fail "$label (exit $rc; see $log)"
    grep -E "error:|TEST FAILED|FAILED" "$log" | head -20 | sed 's/^/      /' || true
  else
    pass "$label"
  fi
}

# Ensure we're in the repo root
cd "$(git rev-parse --show-toplevel)"

# --- Stage 0: SwiftLint ---
stage "SwiftLint"

if command -v swiftlint > /dev/null 2>&1; then
  # Grep the captured log (not the live pipe) so swiftlint's own non-zero exit
  # under pipefail can't masquerade as a clean run. We only care whether the
  # output contains error-level violations; warnings are allowed.
  set +e
  swiftlint --quiet > /tmp/swiftlint.log 2>&1
  set -e
  if grep -q "error:" /tmp/swiftlint.log; then
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
# All builds use `clean build` to avoid incremental-cache false positives.
# This adds ~30-60s per stage but prevents stale DerivedData from masking
# real compile errors (see #60 for the tvOS incident that motivated this).

stage "Build Verification (iOS Simulator)"

run_checked "iOS Simulator build" /tmp/preflight_ios_build.log \
  xcodebuild clean build \
  -project TableTogether.xcodeproj \
  -scheme TableTogether \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

stage "Build Verification (Mac Catalyst)"

run_checked "Mac Catalyst build" /tmp/preflight_mac_build.log \
  xcodebuild clean build \
  -project TableTogether.xcodeproj \
  -scheme TableTogether \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

stage "Build Verification (tvOS Simulator)"

run_checked "tvOS Simulator build" /tmp/preflight_tvos_build.log \
  xcodebuild clean build \
  -project TableTogetherTV/TableTogetherTV.xcodeproj \
  -scheme TableTogetherTV \
  -destination 'generic/platform=tvOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

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
  run_checked "Unit tests" /tmp/preflight_tests.log \
    xcodebuild clean test \
    -project TableTogether.xcodeproj \
    -scheme TableTogether \
    -destination "id=$SIM_ID" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
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
