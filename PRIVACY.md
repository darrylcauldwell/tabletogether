# Privacy Policy — TableTogether

**Effective Date:** February 20, 2026
**Last Updated:** February 20, 2026

## Overview

TableTogether is a meal planning and nutrition tracking app for households, available on iPhone, iPad, Mac, and Apple TV. This privacy policy explains what data we collect, how we use it, and how we protect your privacy.

### Platform-Specific Privacy

- **iPhone, iPad, Mac:** Full access to both shared household features (recipes, meal plans, grocery lists) and private personal features (nutrition logs, health data, insights)
- **Apple TV:** Displays only shared household data (today's meal plan). No personal nutrition data, meal logs, or health information is accessible on Apple TV

## Our Commitment

**Food is shared. Bodies are not.**

- Recipes, meal plans, and grocery lists are collaborative and shared within your household
- Nutrition logs, health data, and personal insights are always private and never shared
- We never enable comparison, judgment, or performance tracking between household members

## Data We Collect

### Health & Fitness Data (Optional)

If you choose to connect Apple Health, TableTogether may access:

- Weight, height, biological sex, and date of birth (for BMR/TDEE calculations)
- Dietary macros: energy, protein, carbohydrates, fat

**How we use it:**
- To help you track meals and dietary goals
- To provide personal nutrition insights
- To log your meal nutrition data to Apple Health

**Important:**
- HealthKit data is used solely for personal health management
- Never used for marketing or advertising
- You must explicitly connect to Apple Health — the app is fully functional without it
- HealthKit data remains on your device per Apple's requirements

### Meal Planning Data

Data shared within your household via iCloud CloudKit:

- Recipes and ingredients
- Meal plans and calendar entries
- Grocery lists and pantry items
- Household membership

### Personal Nutrition Data (Never Shared)

Data private to you:

- Meal consumption logs
- Portion sizes
- Daily nutrition totals
- Personal targets and goals
- Nutrition insights and trends

**This data is encrypted in your private iCloud storage and never accessible to other household members.**

## Data We Do NOT Collect

- No advertising identifiers
- No analytics or tracking SDKs
- No third-party data sharing
- No email, phone number, or demographic data
- No location data
- No social media integration

## How We Store Data

All data is stored via Apple CloudKit:

- **Shared data:** CloudKit Shared Database (recipes, meal plans, grocery lists)
- **Personal data:** CloudKit Private Database (meal logs, health data, nutrition targets)
- **HealthKit data:** Remains on-device only, per Apple's requirements
- **No server-side storage** outside Apple's infrastructure

Your data is encrypted both in transit and at rest using Apple's security infrastructure.

## Third-Party Services

### USDA FoodData Central

We query the USDA FoodData Central database to estimate nutrition for foods you log.

- Queries contain only food names (e.g., "banana")
- No user identifiers or personal information is sent
- USDA data is public domain and lab-verified

### Open Food Facts

We query the Open Food Facts database (ODbL community database) for packaged food nutrition.

- Queries contain only food names or barcodes
- No user identifiers or personal information is sent
- Anonymous lookups only

### AI Parsing (On-Device)

When you use the "Describe it" meal logging feature:

- AI parsing uses Apple's on-device FoundationModels framework (iOS 18+)
- Processing happens entirely on your device
- No meal descriptions leave your device
- Fallback to regex parsing if AI is unavailable

## Data Sharing Within Households

When you join or create a household:

- Recipes, meal plans, and grocery lists are shared with household members via CloudKit
- Personal meal logs, health data, and nutrition targets are **never** shared
- Any household member can add, edit, or delete shared recipes and meal plans
- There are no "admins" or permission levels — all members are equal
- **Apple TV app:** Displays only shared household meal plans for the day. No personal data, meal logs, or nutrition information is shown on Apple TV

## Data Deletion

### Delete Personal Data

- Delete individual meal logs in-app (swipe to delete)
- Disconnect from Apple Health in Settings → Apple Health
- Deleting the app removes all local and iCloud data associated with your Apple ID

### Leave a Household

- Tap "Leave Household" in Settings
- Removes your access to shared recipes and meal plans
- Your personal meal logs and health data remain private to you

### Delete Shared Data

- Any household member can delete shared recipes, meal plans, or grocery items
- Deletion syncs to all household members

## Children's Privacy

- TableTogether does not target children under 13
- We do not knowingly collect data from children under 13
- No COPPA-regulated data collection

## Your Rights

You have the right to:

- Access your data (via iCloud settings)
- Delete your data (by deleting the app or specific entries)
- Disconnect from Apple Health at any time
- Leave a household and revoke access to shared data

## No Account Required

TableTogether uses iCloud with your Apple ID. There is no separate account creation, login, or password.

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted at this URL with an updated "Last Updated" date.

## Contact Us

If you have questions about this privacy policy or how we handle your data:

**Support:** https://github.com/darrylcauldwell/tabletogether/issues
**Email:** darryl_cauldwell@hotmail.com

## Legal

TableTogether is developed by Darryl Cauldwell.

Nutrition estimates are approximate, sourced from USDA FoodData Central and Open Food Facts. TableTogether is not a substitute for professional dietary advice. Consult a healthcare provider before making dietary changes.

---

**Copyright © 2026 Darryl Cauldwell. All rights reserved.**
