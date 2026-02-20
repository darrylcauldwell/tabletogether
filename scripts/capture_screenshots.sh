#!/usr/bin/env bash
#
# capture_screenshots.sh
#
# Captures App Store screenshots from iOS/iPadOS simulators.
# Creates temporary simulators, builds the app once, enables demo data,
# then loops through each device/tab combination capturing screenshots.
#
# Usage:
#   ./scripts/capture_screenshots.sh [--keep-simulators]
#
# Output:
#   fastlane/screenshots/en-GB/{device}_{order}_{TabName}.png

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/TableTogether.xcodeproj"
TVOS_PROJECT_FILE="$PROJECT_DIR/TableTogetherTV.xcodeproj"
SCHEME="TableTogether"
TVOS_SCHEME="TableTogetherTV"
BUNDLE_ID="dev.dreamfold.tabletogether"
TVOS_BUNDLE_ID="dev.dreamfold.tabletogether.tv"
SCREENSHOT_DIR="$PROJECT_DIR/fastlane/screenshots/en-GB"
DERIVED_DATA_DIR="$PROJECT_DIR/build/DerivedData"

KEEP_SIMULATORS=false
if [[ "${1:-}" == "--keep-simulators" ]]; then
    KEEP_SIMULATORS=true
fi

# Simulator definitions: name|device type|screenshot prefix
IPHONE_67_NAME="Screenshot-iPhone16ProMax"
IPHONE_67_DEVICE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
IPHONE_67_PREFIX="iphone_6_7"

IPHONE_61_NAME="Screenshot-iPhone16Pro"
IPHONE_61_DEVICE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
IPHONE_61_PREFIX="iphone_6_1"

IPAD_13_NAME="Screenshot-iPadPro13M5"
IPAD_13_DEVICE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
IPAD_13_PREFIX="ipad_13"

TVOS_NAME="Screenshot-AppleTV4K"
TVOS_DEVICE="com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K"
TVOS_PREFIX="appletv"

# Tabs per device category
IPHONE_TABS=("plan" "recipes" "grocery" "log" "insights")
IPAD_TABS=("plan" "recipes" "pantryCheck" "grocery" "log" "insights")
TVOS_TABS=("today" "thisWeek" "recipes" "inspiration")

# Collect created simulator UDIDs for cleanup
CREATED_SIMULATORS=()

# Tab display name lookup (bash 3.x compatible)
get_tab_display_name() {
    case "$1" in
        plan) echo "Plan" ;;
        recipes) echo "Recipes" ;;
        pantryCheck) echo "PantryCheck" ;;
        grocery) echo "Shopping" ;;
        log) echo "Log" ;;
        insights) echo "Insights" ;;
        today) echo "Today" ;;
        thisWeek) echo "ThisWeek" ;;
        inspiration) echo "Inspiration" ;;
        *) echo "$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    echo "==> $*"
}

error() {
    echo "ERROR: $*" >&2
}

# Cleanup function — deletes simulators unless --keep-simulators
cleanup() {
    # Handle empty array for bash 3.x with set -u
    if [[ ${#CREATED_SIMULATORS[@]} -eq 0 ]]; then
        return
    fi

    if [[ "$KEEP_SIMULATORS" == true ]]; then
        log "Keeping simulators (--keep-simulators):"
        for udid in "${CREATED_SIMULATORS[@]}"; do
            echo "    $udid"
        done
        return
    fi

    log "Cleaning up simulators..."
    for udid in "${CREATED_SIMULATORS[@]}"; do
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        xcrun simctl delete "$udid" 2>/dev/null || true
        log "  Deleted $udid"
    done
}

trap cleanup EXIT

# Get the latest iOS runtime available
get_latest_runtime() {
    xcrun simctl list runtimes -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
runtimes = [r for r in data['runtimes'] if r['isAvailable'] and r['platform'] == 'iOS']
runtimes.sort(key=lambda r: r['version'], reverse=True)
if runtimes:
    print(runtimes[0]['identifier'])
else:
    sys.exit(1)
"
}

# Get the latest tvOS runtime available
get_latest_tvos_runtime() {
    xcrun simctl list runtimes -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
runtimes = [r for r in data['runtimes'] if r['isAvailable'] and r['platform'] == 'tvOS']
runtimes.sort(key=lambda r: r['version'], reverse=True)
if runtimes:
    print(runtimes[0]['identifier'])
else:
    sys.exit(1)
"
}

# Create a simulator, returns UDID
create_simulator() {
    local name="$1"
    local device_type="$2"
    local runtime="$3"

    # Delete any existing simulator with the same name
    local existing
    existing=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime_id, devices in data['devices'].items():
    for d in devices:
        if d['name'] == '$name':
            print(d['udid'])
            sys.exit(0)
" 2>/dev/null || true)

    if [[ -n "$existing" ]]; then
        echo "  Removing existing simulator '$name' ($existing)" >&2
        xcrun simctl shutdown "$existing" 2>/dev/null || true
        xcrun simctl delete "$existing" 2>/dev/null || true
    fi

    local udid
    udid=$(xcrun simctl create "$name" "$device_type" "$runtime")
    CREATED_SIMULATORS+=("$udid")
    echo "$udid"
}

# Boot a simulator and wait for it to be ready
boot_simulator() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    # Wait for the simulator to finish booting
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        local state
        state=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime_id, devices in data['devices'].items():
    for d in devices:
        if d['udid'] == '$udid':
            print(d['state'])
            sys.exit(0)
" 2>/dev/null || echo "Unknown")
        if [[ "$state" == "Booted" ]]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    error "Simulator $udid did not boot within ${max_wait}s"
    return 1
}

# Override status bar to show 9:41, full battery, full signal
override_status_bar() {
    local udid="$1"
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --batteryState charged \
        --batteryLevel 100 \
        --wifiBars 3 \
        --cellularBars 4 \
        --dataNetwork "wifi" \
        --operatorName "" 2>/dev/null || true
}

# Install the app on a simulator
install_app() {
    local udid="$1"
    local app_path="$2"
    xcrun simctl install "$udid" "$app_path"
}

# Enable demo data via UserDefaults before app launch
enable_demo_data_defaults() {
    local udid="$1"
    xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" isDemoDataEnabled -bool true
}

# Launch app with screenshot arguments
launch_app() {
    local udid="$1"
    shift
    xcrun simctl launch "$udid" "$BUNDLE_ID" "$@"
}

# Terminate the app
terminate_app() {
    local udid="$1"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
}

# Capture a screenshot
capture_screenshot() {
    local udid="$1"
    local output_path="$2"
    xcrun simctl io "$udid" screenshot --type=png "$output_path"
}

# Find the built .app bundle
find_app_bundle() {
    local app_path
    app_path=$(find "$DERIVED_DATA_DIR" -path "*/Build/Products/Debug-iphonesimulator/TableTogether.app" -type d 2>/dev/null | head -1)
    if [[ -z "$app_path" ]]; then
        error "Could not find built .app bundle"
        return 1
    fi
    echo "$app_path"
}

# Find the built tvOS .app bundle
find_tvos_app_bundle() {
    local app_path
    app_path=$(find "$DERIVED_DATA_DIR" -path "*/Build/Products/Debug-appletvsimulator/TableTogetherTV.app" -type d 2>/dev/null | head -1)
    if [[ -z "$app_path" ]]; then
        error "Could not find built tvOS .app bundle"
        return 1
    fi
    echo "$app_path"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    log "Starting screenshot capture..."
    log "Project: $PROJECT_FILE"

    # 1. Determine runtime
    log "Finding latest iOS runtime..."
    local runtime
    runtime=$(get_latest_runtime)
    log "Using runtime: $runtime"

    # 2. Create simulators
    log "Creating simulators..."

    log "  Creating $IPHONE_67_NAME..."
    local iphone_67_udid
    iphone_67_udid=$(create_simulator "$IPHONE_67_NAME" "$IPHONE_67_DEVICE" "$runtime")
    log "  Created: $iphone_67_udid"

    log "  Creating $IPHONE_61_NAME..."
    local iphone_61_udid
    iphone_61_udid=$(create_simulator "$IPHONE_61_NAME" "$IPHONE_61_DEVICE" "$runtime")
    log "  Created: $iphone_61_udid"

    log "  Creating $IPAD_13_NAME..."
    local ipad_13_udid
    ipad_13_udid=$(create_simulator "$IPAD_13_NAME" "$IPAD_13_DEVICE" "$runtime")
    log "  Created: $ipad_13_udid"

    # 2b. Create tvOS simulator
    log "Finding latest tvOS runtime..."
    local tvos_runtime
    tvos_runtime=$(get_latest_tvos_runtime) || {
        log "WARNING: tvOS runtime not found, skipping tvOS screenshots"
        tvos_runtime=""
    }

    local tvos_udid=""
    if [[ -n "$tvos_runtime" ]]; then
        log "Using tvOS runtime: $tvos_runtime"
        log "  Creating $TVOS_NAME..."
        tvos_udid=$(create_simulator "$TVOS_NAME" "$TVOS_DEVICE" "$tvos_runtime")
        log "  Created: $tvos_udid"
    fi

    # 3. Strip extended attributes (iCloud Drive adds resource forks that break code signing)
    log "Stripping extended attributes from project..."
    xattr -rc "$PROJECT_DIR" 2>/dev/null || true

    # 4. Clean derived data to avoid stale builds with resource forks
    log "Cleaning derived data..."
    rm -rf "$DERIVED_DATA_DIR"

    # 5. Build the app once (targeting one of the iPhone simulators)
    # Disable code signing since simulators don't need it and iCloud Drive adds
    # extended attributes that break the codesign step
    log "Building app for iOS Simulator..."
    xcodebuild build \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "id=$iphone_67_udid" \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        -quiet

    local app_path
    app_path=$(find_app_bundle)
    log "Built app: $app_path"

    # 5b. Build tvOS app if runtime available
    local tvos_app_path=""
    if [[ -n "$tvos_udid" ]]; then
        log "Building app for tvOS Simulator..."
        xcodebuild build \
            -project "$TVOS_PROJECT_FILE" \
            -scheme "$TVOS_SCHEME" \
            -destination "id=$tvos_udid" \
            -derivedDataPath "$DERIVED_DATA_DIR" \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            -quiet

        tvos_app_path=$(find_tvos_app_bundle)
        log "Built tvOS app: $tvos_app_path"
    fi

    # 6. Create output directory
    mkdir -p "$SCREENSHOT_DIR"

    # 7. Process each device
    process_device() {
        local udid="$1"
        local prefix="$2"
        shift 2
        local tabs=("$@")

        log "Processing device: $prefix ($udid)"

        # Boot
        log "  Booting simulator..."
        boot_simulator "$udid"

        # Override status bar
        log "  Overriding status bar..."
        override_status_bar "$udid"

        # Install app
        log "  Installing app..."
        install_app "$udid" "$app_path"

        # Enable demo data defaults
        log "  Enabling demo data defaults..."
        enable_demo_data_defaults "$udid"

        # Initial launch to seed demo data
        log "  Seeding demo data (initial launch)..."
        launch_app "$udid" --screenshot-mode --screenshot-tab plan
        sleep 8
        terminate_app "$udid"
        sleep 2

        # Capture each tab
        local order=1
        for tab in "${tabs[@]}"; do
            local display_name
            display_name=$(get_tab_display_name "$tab")
            local filename="${prefix}_$(printf '%02d' $order)_${display_name}.png"
            local output_path="$SCREENSHOT_DIR/$filename"

            log "  Capturing tab '$tab' -> $filename"

            launch_app "$udid" --screenshot-mode --screenshot-tab "$tab"
            sleep 5
            capture_screenshot "$udid" "$output_path"
            terminate_app "$udid"
            sleep 1

            order=$((order + 1))
        done

        # Shutdown simulator
        log "  Shutting down simulator..."
        xcrun simctl shutdown "$udid" 2>/dev/null || true
    }

    # Process tvOS device (separate function due to different bundle ID)
    process_tvos_device() {
        local udid="$1"
        local prefix="$2"
        local tvos_app="$3"
        shift 3
        local tabs=("$@")

        log "Processing tvOS device: $prefix ($udid)"

        # Boot
        log "  Booting tvOS simulator..."
        boot_simulator "$udid"

        # Install app
        log "  Installing tvOS app..."
        xcrun simctl install "$udid" "$tvos_app"

        # Enable demo data defaults for tvOS
        log "  Enabling demo data defaults..."
        xcrun simctl spawn "$udid" defaults write "$TVOS_BUNDLE_ID" isDemoDataEnabled -bool true

        # Initial launch to seed demo data
        log "  Seeding demo data (initial launch)..."
        xcrun simctl launch "$udid" "$TVOS_BUNDLE_ID" --screenshot-mode --screenshot-tab today
        sleep 10
        xcrun simctl terminate "$udid" "$TVOS_BUNDLE_ID" 2>/dev/null || true
        sleep 2

        # Capture each tab
        local order=1
        for tab in "${tabs[@]}"; do
            local display_name
            display_name=$(get_tab_display_name "$tab")
            local filename="${prefix}_$(printf '%02d' $order)_${display_name}.png"
            local output_path="$SCREENSHOT_DIR/$filename"

            log "  Capturing tab '$tab' -> $filename"

            xcrun simctl launch "$udid" "$TVOS_BUNDLE_ID" --screenshot-mode --screenshot-tab "$tab"
            sleep 6
            capture_screenshot "$udid" "$output_path"
            xcrun simctl terminate "$udid" "$TVOS_BUNDLE_ID" 2>/dev/null || true
            sleep 1

            order=$((order + 1))
        done

        # Shutdown simulator
        log "  Shutting down tvOS simulator..."
        xcrun simctl shutdown "$udid" 2>/dev/null || true
    }

    process_device "$iphone_67_udid" "$IPHONE_67_PREFIX" "${IPHONE_TABS[@]}"
    process_device "$iphone_61_udid" "$IPHONE_61_PREFIX" "${IPHONE_TABS[@]}"
    process_device "$ipad_13_udid" "$IPAD_13_PREFIX" "${IPAD_TABS[@]}"

    # 8. Process tvOS device
    if [[ -n "$tvos_udid" && -n "$tvos_app_path" ]]; then
        process_tvos_device "$tvos_udid" "$TVOS_PREFIX" "$tvos_app_path" "${TVOS_TABS[@]}"
    fi

    # Summary
    log "Screenshot capture complete!"
    log "Output directory: $SCREENSHOT_DIR"
    log "Files:"
    ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null || log "  (no files found)"
}

main "$@"
