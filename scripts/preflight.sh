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

# --- Stage 4: Build Verification ---
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

# --- Summary ---
echo ""
echo "==============================="
if [ "$FAIL" -ne 0 ]; then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT PASSED"
exit 0
