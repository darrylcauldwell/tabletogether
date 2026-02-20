#!/bin/bash
#
# TableTogetherTV TestFlight Setup Script
# ======================================
# This script helps you set up and deploy TableTogetherTV to TestFlight.
#
# Prerequisites:
# 1. Xcode with tvOS platform installed
# 2. Apple Developer account
# 3. App Store Connect API key (created below)
#

set -e

# Configuration
TEAM_ID="N6BK2WX94Z"
BUNDLE_ID="com.darrylcauldwell.tabletogether.tv"
APP_NAME="TableTogetherTV"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=============================================="
echo "  TableTogetherTV TestFlight Setup"
echo "=============================================="
echo ""

# Step 1: Check for tvOS platform
echo "Step 1: Checking tvOS platform..."
if xcodebuild -showsdks | grep -q "appletvos"; then
    echo "  ✓ tvOS SDK found"
else
    echo "  ✗ tvOS SDK not found"
    echo ""
    echo "  Please install tvOS platform in Xcode:"
    echo "  Xcode > Settings > Components > Platforms > tvOS"
    echo ""
    exit 1
fi

# Step 2: Check signing identity
echo ""
echo "Step 2: Checking signing identity..."
if security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "  ✓ Apple Distribution certificate found"
else
    echo "  ✗ No Apple Distribution certificate found"
    echo ""
    echo "  Please create a distribution certificate in:"
    echo "  https://developer.apple.com/account/resources/certificates"
    echo ""
    exit 1
fi

# Step 3: Check for API key
echo ""
echo "Step 3: Checking App Store Connect API key..."
API_KEY_DIR="$HOME/.appstoreconnect/private_keys"
API_KEY_FILE=$(ls "$API_KEY_DIR"/AuthKey_*.p8 2>/dev/null | head -1)

if [ -n "$API_KEY_FILE" ]; then
    API_KEY_ID=$(basename "$API_KEY_FILE" | sed 's/AuthKey_//' | sed 's/.p8//')
    echo "  ✓ API key found: $API_KEY_ID"
else
    echo "  ✗ No API key found"
    echo ""
    echo "  To create an App Store Connect API key:"
    echo "  1. Go to https://appstoreconnect.apple.com/access/api"
    echo "  2. Click '+' to create a new key"
    echo "  3. Name it 'TableTogether CI' with 'App Manager' access"
    echo "  4. Download the .p8 file"
    echo "  5. Note the Key ID and Issuer ID"
    echo "  6. Run: mkdir -p $API_KEY_DIR"
    echo "  7. Move the .p8 file to: $API_KEY_DIR/AuthKey_KEYID.p8"
    echo ""
    echo "  Then set these environment variables:"
    echo "  export APP_STORE_CONNECT_API_KEY_ID='your-key-id'"
    echo "  export APP_STORE_CONNECT_ISSUER_ID='your-issuer-id'"
    echo ""

    read -p "  Do you want to continue without API key? (manual upload) [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 4: Build and Archive
echo ""
echo "Step 4: Building and archiving..."
cd "$PROJECT_DIR"

# Clean build folder
rm -rf build/TableTogetherTV.xcarchive

# Archive
xcodebuild -project TableTogetherTV.xcodeproj \
    -scheme TableTogetherTV \
    -destination "generic/platform=tvOS" \
    -configuration Release \
    -archivePath build/TableTogetherTV.xcarchive \
    archive \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    | xcpretty || xcodebuild -project TableTogetherTV.xcodeproj \
    -scheme TableTogetherTV \
    -destination "generic/platform=tvOS" \
    -configuration Release \
    -archivePath build/TableTogetherTV.xcarchive \
    archive \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

if [ -d "build/TableTogetherTV.xcarchive" ]; then
    echo "  ✓ Archive created successfully"
else
    echo "  ✗ Archive failed"
    exit 1
fi

# Step 5: Export IPA
echo ""
echo "Step 5: Exporting IPA..."
rm -rf build/TableTogetherTV-Export

xcodebuild -exportArchive \
    -archivePath build/TableTogetherTV.xcarchive \
    -exportPath build/TableTogetherTV-Export \
    -exportOptionsPlist ExportOptions.plist

if [ -f "build/TableTogetherTV-Export/TableTogetherTV.ipa" ]; then
    echo "  ✓ IPA exported successfully"
else
    echo "  ✗ Export failed"
    exit 1
fi

# Step 6: Upload to TestFlight
echo ""
echo "Step 6: Uploading to TestFlight..."

if [ -n "$API_KEY_FILE" ] && [ -n "$APP_STORE_CONNECT_API_KEY_ID" ] && [ -n "$APP_STORE_CONNECT_ISSUER_ID" ]; then
    # Upload using API key
    xcrun altool --upload-app \
        -f build/TableTogetherTV-Export/TableTogetherTV.ipa \
        -t tvos \
        --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
        --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

    echo ""
    echo "  ✓ Upload complete!"
    echo ""
    echo "  Your app is now processing on App Store Connect."
    echo "  Check status at: https://appstoreconnect.apple.com"
else
    echo ""
    echo "  Manual upload required (no API key configured)"
    echo ""
    echo "  Option A: Use Xcode Organizer"
    echo "    1. Open Xcode"
    echo "    2. Window > Organizer"
    echo "    3. Select TableTogetherTV archive"
    echo "    4. Click 'Distribute App'"
    echo "    5. Select 'App Store Connect' > 'Upload'"
    echo ""
    echo "  Option B: Use Transporter app"
    echo "    1. Download 'Transporter' from Mac App Store"
    echo "    2. Drag build/TableTogetherTV-Export/TableTogetherTV.ipa to Transporter"
    echo "    3. Click 'Deliver'"
    echo ""
    echo "  Archive location: $PROJECT_DIR/build/TableTogetherTV.xcarchive"
    echo "  IPA location: $PROJECT_DIR/build/TableTogetherTV-Export/TableTogetherTV.ipa"
fi

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
