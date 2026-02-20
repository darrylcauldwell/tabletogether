# TableTogether

**Plan meals together. Cook step by step. Track nutrition privately.**

TableTogether is a meal planning and nutrition tracking app for households who share a kitchen. Built natively for iPhone, iPad, Mac, and Apple TV.

![Platform: iOS 18+ | iPadOS 18+ | macOS 15+ | tvOS 18+](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-lightgrey)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

## Features

### 🗓️ Plan Together
- Visual week planner with drag-and-drop
- Smart suggestions based on your household's favorites
- Sync meal plans across all devices via iCloud

### 📖 Three Ways to Add Recipes
- Build recipes by hand with rich editing
- Import from any recipe website (URL paste)
- AI-generated recipes from ingredients you have

### 👨‍🍳 Cook Step by Step
- Full-screen Cooking Mode with large text
- Built-in timer and ingredient checklist
- Designed for messy hands and busy kitchens

### 🛒 Shop Smarter
- Mark pantry items you already have
- Auto-generated shopping lists organized by aisle
- Sync across household members

### 🥗 Describe What You Ate
- Type meals in plain language (e.g., "two eggs on toast with butter")
- On-device AI parsing with USDA nutrition estimates
- Tap ingredients to refine portion sizes

### 📊 Private Insights
- Personal meal logs and nutrition trends
- Weekly patterns shown without judgment
- No streaks, scores, or comparisons
- Optional Apple Health sync

### 📺 Apple TV Ambient Display
- View today's meals on the big screen
- Like a kitchen whiteboard in your living room
- Read-only, calm interface

## Core Principle

**Food is shared. Bodies are not.**

- Recipes, meal plans, and grocery lists are collaborative
- Nutrition logs, targets, and insights are always private
- The app never enables comparison, judgment, or shame

## Screenshots

| iPhone | iPad | Apple TV |
|--------|------|----------|
| Week planner | Full grid view | Today's meals |
| Recipe detail | Recipe library | This week's plan |
| Meal logging | Cooking mode | Recipe inspiration |

## Technology

- **Language:** Swift 6
- **UI Framework:** SwiftUI
- **Data Sync:** CloudKit (Shared + Private databases)
- **Health Integration:** HealthKit
- **Nutrition Data:** USDA FoodData Central, Open Food Facts
- **AI Parsing:** Apple FoundationModels (on-device)
- **Platforms:** iOS 18+, iPadOS 18+, macOS 15+, tvOS 18+

## Privacy

TableTogether is designed with privacy as a core principle:

- **Shared data:** Recipes, meal plans, grocery lists (via CloudKit Shared Database)
- **Private data:** Meal logs, health data, nutrition targets (via CloudKit Private Database)
- **No servers:** All data stored in your iCloud account
- **No tracking:** No analytics, ads, or third-party SDKs
- **No account:** Uses your Apple ID via CloudKit

Read the full [Privacy Policy](PRIVACY.md).

## Building

### Requirements

- Xcode 16+
- iOS 18+ SDK
- Apple Developer account (for iCloud/HealthKit entitlements)

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/darrylcauldwell/tabletogether.git
   cd tabletogether
   ```

2. Open the project:
   ```bash
   open TableTogether.xcodeproj
   ```

3. Update the bundle identifier and team ID in Xcode:
   - Select the project in the navigator
   - Update `PRODUCT_BUNDLE_IDENTIFIER` to your own
   - Set your development team under Signing & Capabilities

4. Build and run on your device or simulator.

### Project Structure

```
TableTogether/
├── Sources/           # Swift source files
├── Assets.xcassets/   # App icons and images
├── Package.swift      # Swift Package Manager manifest
└── *.entitlements     # iCloud, HealthKit, Calendar entitlements

TableTogetherTV/       # tvOS-specific target
├── Sources/
├── Assets.xcassets/
└── Info.plist
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- **Issues:** [GitHub Issues](https://github.com/darrylcauldwell/tabletogether/issues)
- **Email:** darryl_cauldwell@hotmail.com

## Acknowledgments

- Nutrition data from [USDA FoodData Central](https://fdc.nal.usda.gov/) (public domain)
- Additional data from [Open Food Facts](https://world.openfoodfacts.org/) (ODbL)
- Inspired by Things 3, MacroFactor, and Paprika

---

**Copyright © 2026 Darryl Cauldwell. All rights reserved.**
