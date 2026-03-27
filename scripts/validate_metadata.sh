#!/usr/bin/env bash
# Validates fastlane/metadata character limits for App Store Connect
set -euo pipefail

FAIL=0

check_limit() {
  local file="$1"
  local limit="$2"
  local label="$3"

  if [ ! -f "$file" ]; then
    return
  fi

  local count
  count=$(wc -m < "$file" | tr -d ' ')

  if [ "$count" -gt "$limit" ]; then
    echo "::error file=${file}::${label} is ${count} chars (limit ${limit})"
    FAIL=1
  else
    echo "  ✓ ${label}: ${count}/${limit}"
  fi
}

echo "Checking metadata character limits..."

for locale in fastlane/metadata/*/; do
  locale_name=$(basename "$locale")
  echo ""
  echo "Locale: ${locale_name}"

  check_limit "${locale}name.txt"             30   "name"
  check_limit "${locale}subtitle.txt"         30   "subtitle"
  check_limit "${locale}keywords.txt"        100   "keywords"
  check_limit "${locale}description.txt"    4000   "description"
  check_limit "${locale}promotional_text.txt" 170  "promotional_text"
  check_limit "${locale}release_notes.txt"  4000   "release_notes"
done

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "FAIL: One or more metadata fields exceed character limits"
  exit 1
fi

echo ""
echo "All metadata within limits."
