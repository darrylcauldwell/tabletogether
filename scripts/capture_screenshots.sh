#!/bin/bash
#
# TableTogether - simctl-based App Store Screenshot Pipeline
# ===========================================================
#
# Captures screenshots by launching the app with --screenshot-mode --screenshot-screen <name>,
# then capturing with simctl io. No XCTest involved.
#
# Usage:
#   ./scripts/capture_screenshots.sh                # All devices
#   ./scripts/capture_screenshots.sh --iphone-only  # iPhone only
#   ./scripts/capture_screenshots.sh --ipad-only    # iPad only
#   ./scripts/capture_screenshots.sh --tvos-only    # tvOS only
#   ./scripts/capture_screenshots.sh --keep-simulators  # Don't delete simulators after
#
# Output: fastlane/screenshots/en-GB/ (copied to en-US/)
#

set -euo pipefail

# -----------------------------------------------
# Configuration
# -----------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_LIB="${HOME}/.claude/shared/screenshot-lib.sh"

if [ ! -f "$SHARED_LIB" ]; then
    echo "Error: Shared screenshot library not found at ${SHARED_LIB}"
    exit 1
fi
source "$SHARED_LIB"

BUNDLE_ID="dev.dreamfold.tabletogether"
TVOS_BUNDLE_ID="dev.dreamfold.tabletogether.tv"
PROJECT="${PROJECT_DIR}/TableTogether.xcodeproj"
TVOS_PROJECT="${PROJECT_DIR}/TableTogetherTV.xcodeproj"
SCHEME="TableTogether"
TVOS_SCHEME="TableTogetherTV"
DERIVED_DATA="/tmp/TableTogetherScreenshotBuild"
OUTPUT_DIR="${PROJECT_DIR}/fastlane/screenshots"
SETTLE_TIME=5

# Device configurations
IPHONE_67_NAME="Screenshot_iPhone_6.7"
IPHONE_67_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"

IPHONE_61_NAME="Screenshot_iPhone_6.1"
IPHONE_61_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"

IPAD_13_NAME="Screenshot_iPad_13"
IPAD_13_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5"

TVOS_NAME="Screenshot_AppleTV4K"
TVOS_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K"

# iPhone screens
IPHONE_SCREENS=(
    "plan"
    "recipes"
    "grocery"
    "log"
    "insights"
)

IPHONE_FILENAMES=(
    "01_Plan"
    "02_Recipes"
    "03_Shopping"
    "04_Log"
    "05_Insights"
)

# iPad screens
IPAD_SCREENS=(
    "plan"
    "recipes"
    "pantryCheck"
    "grocery"
    "log"
    "insights"
)

IPAD_FILENAMES=(
    "iPad_01_Plan"
    "iPad_02_Recipes"
    "iPad_03_PantryCheck"
    "iPad_04_Shopping"
    "iPad_05_Log"
    "iPad_06_Insights"
)

# tvOS screens
TVOS_SCREENS=(
    "today"
    "thisWeek"
    "recipes"
    "inspiration"
)

TVOS_FILENAMES=(
    "AppleTV_01_Today"
    "AppleTV_02_ThisWeek"
    "AppleTV_03_Recipes"
    "AppleTV_04_Inspiration"
)

# -----------------------------------------------
# Parse Arguments
# -----------------------------------------------

RUN_IPHONE=true
RUN_IPAD=true
RUN_TVOS=true
KEEP_SIMULATORS=false

for arg in "$@"; do
    case $arg in
        --iphone-only) RUN_IPAD=false; RUN_TVOS=false ;;
        --ipad-only) RUN_IPHONE=false; RUN_TVOS=false ;;
        --tvos-only) RUN_IPHONE=false; RUN_IPAD=false ;;
        --keep-simulators) KEEP_SIMULATORS=true ;;
    esac
done

echo "==============================================="
echo "TableTogether Screenshot Pipeline (simctl)"
echo "==============================================="
echo ""

# -----------------------------------------------
# Build Once
# -----------------------------------------------

if [ "$RUN_IPHONE" = true ] || [ "$RUN_IPAD" = true ]; then
    echo "Step 1: Building iOS app..."
    screenshot_build_app "$PROJECT" "$SCHEME" "$DERIVED_DATA"

    APP_BUNDLE=$(screenshot_find_app_bundle "$DERIVED_DATA" "TableTogether")
    if [ -z "$APP_BUNDLE" ]; then
        echo "Error: Could not find TableTogether.app in derived data"
        exit 1
    fi
    echo "App bundle: ${APP_BUNDLE}"
    echo ""
fi

# -----------------------------------------------
# Capture Function (iOS/iPadOS)
# -----------------------------------------------

capture_device() {
    local sim_name="$1"
    local sim_type="$2"
    local label="$3"
    local -n screens_ref=$4
    local -n filenames_ref=$5
    local output_subdir="$6"

    local dest="${OUTPUT_DIR}/${output_subdir}"
    mkdir -p "$dest"

    echo "[$label] Creating simulator: ${sim_name}..."
    local udid
    udid=$(screenshot_create_simulator "$sim_name" "$sim_type")
    echo "[$label] Simulator UDID: ${udid}"

    echo "[$label] Booting simulator..."
    screenshot_boot_simulator "$udid"
    screenshot_override_status_bar "$udid"

    echo "[$label] Installing app..."
    screenshot_install_app "$udid" "$APP_BUNDLE"

    # Enable demo data and seed with initial launch
    xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" isDemoDataEnabled -bool true
    echo "[$label] Seeding demo data..."
    screenshot_launch_app "$udid" "$BUNDLE_ID" "${screens_ref[0]}"
    sleep 8
    screenshot_terminate_app "$udid" "$BUNDLE_ID"
    sleep 2

    echo "[$label] Capturing ${#screens_ref[@]} screens..."
    for i in "${!screens_ref[@]}"; do
        local screen="${screens_ref[$i]}"
        local filename="${filenames_ref[$i]}"
        local output_path="${dest}/${filename}.png"
        screenshot_capture_screen "$udid" "$BUNDLE_ID" "$screen" "$output_path" "$SETTLE_TIME"
    done

    if [ "$KEEP_SIMULATORS" = false ]; then
        echo "[$label] Cleaning up simulator..."
        screenshot_delete_simulator "$udid"
    else
        echo "[$label] Keeping simulator (UDID: ${udid})"
    fi

    echo "[$label] Done — ${#screens_ref[@]} screenshots captured"
    echo ""
}

# -----------------------------------------------
# Capture Function (tvOS)
# -----------------------------------------------

capture_tvos_device() {
    local sim_name="$1"
    local sim_type="$2"
    local label="$3"
    local -n screens_ref=$4
    local -n filenames_ref=$5
    local output_subdir="$6"

    local dest="${OUTPUT_DIR}/${output_subdir}"
    mkdir -p "$dest"

    # Build tvOS app
    echo "[$label] Building tvOS app..."
    local tvos_derived="/tmp/TableTogetherTVScreenshotBuild"
    screenshot_build_app "$TVOS_PROJECT" "$TVOS_SCHEME" "$tvos_derived"

    local tvos_app
    tvos_app=$(find "$tvos_derived" -path "*/Build/Products/Debug-appletvsimulator/TableTogetherTV.app" -type d | head -1)
    if [ -z "$tvos_app" ]; then
        echo "Error: Could not find TableTogetherTV.app in derived data"
        return 1
    fi

    echo "[$label] Creating simulator: ${sim_name}..."
    local udid
    udid=$(screenshot_create_simulator "$sim_name" "$sim_type" "com.apple.CoreSimulator.SimRuntime.tvOS-26-0")
    echo "[$label] Simulator UDID: ${udid}"

    echo "[$label] Booting simulator..."
    screenshot_boot_simulator "$udid"

    echo "[$label] Installing app..."
    xcrun simctl install "$udid" "$tvos_app"

    # Enable demo data and seed
    xcrun simctl spawn "$udid" defaults write "$TVOS_BUNDLE_ID" isDemoDataEnabled -bool true
    echo "[$label] Seeding demo data..."
    xcrun simctl launch "$udid" "$TVOS_BUNDLE_ID" --screenshot-mode --screenshot-screen "${screens_ref[0]}"
    sleep 10
    xcrun simctl terminate "$udid" "$TVOS_BUNDLE_ID" 2>/dev/null || true
    sleep 2

    echo "[$label] Capturing ${#screens_ref[@]} screens..."
    for i in "${!screens_ref[@]}"; do
        local screen="${screens_ref[$i]}"
        local filename="${filenames_ref[$i]}"
        local output_path="${dest}/${filename}.png"

        xcrun simctl terminate "$udid" "$TVOS_BUNDLE_ID" 2>/dev/null || true
        sleep 0.5
        xcrun simctl launch "$udid" "$TVOS_BUNDLE_ID" --screenshot-mode --screenshot-screen "$screen"
        sleep 6
        screenshot_capture "$udid" "$output_path"
        echo "  Captured: ${filename}.png"
        xcrun simctl terminate "$udid" "$TVOS_BUNDLE_ID" 2>/dev/null || true
    done

    if [ "$KEEP_SIMULATORS" = false ]; then
        echo "[$label] Cleaning up simulator..."
        screenshot_delete_simulator "$udid"
    else
        echo "[$label] Keeping simulator (UDID: ${udid})"
    fi

    echo "[$label] Done — ${#screens_ref[@]} screenshots captured"
    echo ""
}

# -----------------------------------------------
# Capture Screenshots
# -----------------------------------------------

echo "Step 2: Capturing screenshots..."
echo ""

if [ "$RUN_IPHONE" = true ]; then
    capture_device "$IPHONE_67_NAME" "$IPHONE_67_TYPE" "iPhone 6.7\"" \
        IPHONE_SCREENS IPHONE_FILENAMES "en-GB"

    capture_device "$IPHONE_61_NAME" "$IPHONE_61_TYPE" "iPhone 6.1\"" \
        IPHONE_SCREENS IPHONE_FILENAMES "en-GB/6.1"
fi

if [ "$RUN_IPAD" = true ]; then
    capture_device "$IPAD_13_NAME" "$IPAD_13_TYPE" "iPad 13\"" \
        IPAD_SCREENS IPAD_FILENAMES "en-GB"
fi

if [ "$RUN_TVOS" = true ]; then
    capture_tvos_device "$TVOS_NAME" "$TVOS_TYPE" "Apple TV 4K" \
        TVOS_SCREENS TVOS_FILENAMES "en-GB"
fi

# -----------------------------------------------
# Copy Locale
# -----------------------------------------------

echo "Step 3: Copying en-GB to en-US..."
screenshot_copy_locale "${OUTPUT_DIR}/en-GB" "${OUTPUT_DIR}/en-US"
if [ -d "${OUTPUT_DIR}/en-GB/6.1" ]; then
    screenshot_copy_locale "${OUTPUT_DIR}/en-GB/6.1" "${OUTPUT_DIR}/en-US/6.1"
fi
echo ""

# -----------------------------------------------
# Summary
# -----------------------------------------------

echo "==============================================="
echo "Screenshot Pipeline Complete"
echo "==============================================="
echo ""

if [ -d "${OUTPUT_DIR}/en-GB" ]; then
    total_count=$(find "${OUTPUT_DIR}/en-GB" -maxdepth 1 -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    echo "Total: ${total_count} screenshots in en-GB/ (copied to en-US/)"
    echo ""
    find "${OUTPUT_DIR}/en-GB" -maxdepth 1 -name "*.png" -exec basename {} \; | sort | while read f; do echo "  $f"; done
    echo ""
fi

echo "Output: ${OUTPUT_DIR}/en-GB/ and ${OUTPUT_DIR}/en-US/"
echo "Upload to App Store Connect with: fastlane upload_metadata"
