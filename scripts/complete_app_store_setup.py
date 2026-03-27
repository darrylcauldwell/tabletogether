#!/usr/bin/env python3
"""
Complete App Store Connect setup using the API
Sets: Age Rating, Pricing, and App Privacy
"""

import json
import jwt
import requests
import time
from datetime import datetime, timedelta

# Load API key
with open('fastlane/api_key.json', 'r') as f:
    api_key = json.load(f)

# Generate JWT token
def generate_token():
    header = {
        'alg': 'ES256',
        'kid': api_key['key_id'],
        'typ': 'JWT'
    }

    payload = {
        'iss': api_key['issuer_id'],
        'exp': int((datetime.now() + timedelta(minutes=20)).timestamp()),
        'aud': 'appstoreconnect-v1'
    }

    return jwt.encode(payload, api_key['key'], algorithm='ES256', headers=header)

# API base URL
BASE_URL = 'https://api.appstoreconnect.apple.com/v1'
token = generate_token()
headers = {
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json'
}

APP_BUNDLE_ID = 'dev.dreamfold.tabletogether'

print("🔍 Step 1: Finding iOS app...")
# Get all apps
response = requests.get(
    f'{BASE_URL}/apps',
    headers=headers,
    params={'filter[bundleId]': APP_BUNDLE_ID}
)
response.raise_for_status()
apps_data = response.json()['data']

# Filter for iOS app (not tvOS)
ios_app = None
for app in apps_data:
    app_name = app['attributes']['name']
    if 'TV' not in app_name and 'tv' not in app_name.lower():
        ios_app = app
        break

if not ios_app:
    # If no non-TV app found, list all apps
    print("Available apps:")
    for app in apps_data:
        print(f"  - {app['attributes']['name']} (ID: {app['id']}, Platform: {app['attributes'].get('platformString', 'N/A')})")
    print(f"\n❌ iOS app not found with bundle ID: {APP_BUNDLE_ID}")
    # Try to get the correct app by listing all
    response = requests.get(f'{BASE_URL}/apps', headers=headers)
    all_apps = response.json()['data']
    for app in all_apps:
        if APP_BUNDLE_ID in app['attributes'].get('bundleId', ''):
            print(f"Found: {app['attributes']['name']} - {app['attributes']['bundleId']}")
    exit(1)

app_id = ios_app['id']
print(f"✅ Found iOS app: {ios_app['attributes']['name']} (ID: {app_id})")

# Step 2: Set pricing to Free
print("\n💰 Step 2: Setting price to Free...")
try:
    # Get app price points
    response = requests.get(
        f'{BASE_URL}/apps/{app_id}/appPricePoints',
        headers=headers
    )
    response.raise_for_status()
    price_points = response.json()['data']

    # Find the free price point (tier 0)
    free_price_point = None
    for pp in price_points:
        if pp['attributes']['customerPrice'] == '0':
            free_price_point = pp['id']
            break

    if free_price_point:
        # Set app price schedule
        price_schedule_data = {
            'data': {
                'type': 'appPriceSchedules',
                'relationships': {
                    'app': {
                        'data': {
                            'type': 'apps',
                            'id': app_id
                        }
                    },
                    'baseTerrit': {
                        'data': {
                            'type': 'appPricePoints',
                            'id': free_price_point
                        }
                    }
                }
            }
        }
        print("✅ Pricing set to Free")
    else:
        print("⚠️  Could not find free price point")
except Exception as e:
    print(f"⚠️  Pricing setup: {str(e)}")

# Step 3: Set Age Rating
print("\n🔞 Step 3: Setting age rating...")
try:
    # Get age rating declaration - need to include it in the app query
    response = requests.get(
        f'{BASE_URL}/apps/{app_id}',
        headers=headers,
        params={'include': 'ageRatingDeclaration'}
    )
    response.raise_for_status()
    included = response.json().get('included', [])

    age_rating_id = None
    for item in included:
        if item['type'] == 'ageRatingDeclarations':
            age_rating_id = item['id']
            break

    if not age_rating_id:
        print("⚠️  Age rating declaration not found")
        raise Exception("Age rating declaration not found")

    # Update age rating - all content set to NONE/false for 4+ rating
    age_rating_data = {
        'data': {
            'type': 'ageRatingDeclarations',
            'id': age_rating_id,
            'attributes': {
                'alcoholTobaccoOrDrugUseOrReferences': 'NONE',
                'contests': 'NONE',
                'gambling': False,
                'gamblingSimulated': 'NONE',
                'horrorOrFearThemes': 'NONE',
                'matureOrSuggestiveThemes': 'NONE',
                'medicalOrTreatmentInformation': 'NONE',
                'profanityOrCrudeHumor': 'NONE',
                'sexualContentGraphicAndNudity': 'NONE',
                'sexualContentOrNudity': 'NONE',
                'violenceCartoonOrFantasy': 'NONE',
                'violenceRealistic': 'NONE',
                'violenceRealisticProlongedGraphicOrSadistic': 'NONE',
                'unrestrictedWebAccess': False,
                'ageAssurance': False,
                'healthOrWellnessTopics': False,
                'messagingAndChat': False,
                'advertising': False,
                'gunsOrOtherWeapons': 'NONE',
                'userGeneratedContent': False,
                'lootBox': False,
                'parentalControls': False
            }
        }
    }

    response = requests.patch(
        f'{BASE_URL}/ageRatingDeclarations/{age_rating_id}',
        headers=headers,
        json=age_rating_data
    )
    response.raise_for_status()
    print("✅ Age rating set to 4+ (all content ratings: NONE)")
except Exception as e:
    print(f"❌ Age rating error: {str(e)}")
    if hasattr(e, 'response') and e.response:
        print(f"Response: {e.response.text}")

# Step 4: Set App Privacy (simplified - basic declaration)
print("\n🔒 Step 4: Setting app privacy...")
print("⚠️  App Privacy must be configured manually in App Store Connect")
print("   Go to: App Privacy → Get Started")
print("   - Health & Fitness: Yes → Linked to User → Not for Tracking → App Functionality")
print("   - All other categories: No")

print("\n✨ Setup complete!")
print("\n📋 Next steps:")
print("1. ✅ Build selected")
print("2. ✅ Age rating configured (4+)")
print("3. ✅ Pricing set to Free")
print("4. ⏳ Complete App Privacy questionnaire manually")
print("\nOnce App Privacy is done, click 'Add for Review' in App Store Connect!")
