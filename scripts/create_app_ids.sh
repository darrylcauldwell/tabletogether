#!/bin/bash
#
# Create App IDs and App Store Connect entries for TableTogether apps
# This script uses fastlane and will prompt for Apple ID authentication
#

set -e

echo "=============================================="
echo "  TableTogether App ID & App Store Connect Setup"
echo "=============================================="
echo ""
echo "This script will create:"
echo "  1. App ID: com.darrylcauldwell.tabletogether (iOS/iPadOS)"
echo "  2. App ID: com.darrylcauldwell.tabletogether.tv (tvOS)"
echo "  3. App Store Connect entries for both"
echo ""
echo "You will be prompted to sign in with your Apple ID."
echo ""

# Apple ID configuration
APPLE_ID="darryl_cauldwell@hotmail.com"
TEAM_ID="N6BK2WX94Z"

echo "Using Apple ID: $APPLE_ID"
echo ""

echo "Creating iOS App (com.darrylcauldwell.tabletogether)..."
echo "-------------------------------------------"
fastlane produce create \
    --username "$APPLE_ID" \
    --app_identifier "com.darrylcauldwell.tabletogether" \
    --app_name "TableTogether" \
    --team_id "$TEAM_ID" \
    --sku "tabletogether-ios-001" \
    --platform "ios" \
    --language "en-US" \
    --skip_devcenter

echo ""
echo "Creating tvOS App (com.darrylcauldwell.tabletogether.tv)..."
echo "-------------------------------------------"
fastlane produce create \
    --username "$APPLE_ID" \
    --app_identifier "com.darrylcauldwell.tabletogether.tv" \
    --app_name "TableTogether TV" \
    --team_id "$TEAM_ID" \
    --sku "tabletogether-tv-001" \
    --platform "appletvos" \
    --language "en-US"

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "App IDs and App Store Connect entries created."
echo ""
echo "IMPORTANT: You still need to manually enable capabilities:"
echo "  1. Go to https://developer.apple.com/account/resources/identifiers"
echo "  2. For com.darrylcauldwell.tabletogether, enable: HealthKit, iCloud (CloudKit)"
echo "  3. For com.darrylcauldwell.tabletogether.tv, enable: iCloud (CloudKit)"
echo ""
echo "Then run the archive script again."
echo ""
