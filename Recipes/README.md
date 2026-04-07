# Curated Recipes

A personal, version-controlled collection of recipes that can be imported into TableTogether on demand.

## What this is

- A directory of recipe `.json` files stored in this repo
- Built up over time, often collaboratively with Claude as a research/drafting partner
- Reviewable, diffable, and trackable in git like any other source

## What this is NOT

- **Not bundled in the app** — these files are not included in the iOS/iPadOS/Mac Catalyst/tvOS build. Installing TableTogether from TestFlight does not bring any of these recipes with it.
- **Not auto-loaded** — the app never reads from this directory at runtime. Recipes only enter the app when you explicitly import them.
- **Not a marketplace** — there is no in-app browsing or discovery. This is a personal library, not user-facing content.

## How to use a recipe

1. Grab the `.json` file from this directory (clone the repo, download from GitHub web, AirDrop from your Mac, etc.)
2. Save it somewhere the iOS Files app can see (iCloud Drive, On My iPhone, etc.)
3. In TableTogether, open **Settings → Data → Import Recipe JSON**
4. Pick the file. The recipe lands in your household library and syncs via CloudKit to everyone in the household.

Importing a recipe whose title already exists in your library is a no-op (case-insensitive duplicate check).

## Folder layout

Organise however suits the collection. Suggested patterns:

```
Recipes/
├── README.md
├── weeknight/
│   ├── lemon-chicken-pasta.json
│   └── ...
├── indian/
│   ├── butter-chicken.json
│   └── ...
└── batch-cooking/
    └── ...
```

A single `.json` file may contain either:
- **One recipe** (a JSON object), or
- **An array of recipes** (a JSON array of objects)

The importer accepts both. Use individual files for diff-friendliness; use array files for bulk import convenience.

## File format

Each recipe matches the `CodableRecipe` schema used by the app's existing Export feature, so any recipe exported from TableTogether is a valid curated recipe.

### Schema

```jsonc
{
  "title": "Lemon Chicken Pasta",          // required
  "summary": "A bright, 20-minute dinner.", // optional
  "sourceURL": "https://example.com/...",   // optional
  "servings": 4,                            // required, integer
  "prepTimeMinutes": 10,                    // 0 means "not set"
  "cookTimeMinutes": 15,                    // 0 means "not set"
  "instructions": [                         // ordered list of steps
    "Bring a large pan of salted water to the boil.",
    "Cook the pasta until al dente."
  ],
  "tags": ["weeknight", "pasta"],           // free-form strings
  "suggestedArchetypes": ["quickWeeknight"], // see ArchetypeType enum
  "ingredients": [
    {
      "name": "spaghetti",                  // required
      "quantity": 400,                      // required, double
      "unit": "gram",                       // see MeasurementUnit enum
      "preparationNote": null,              // optional, e.g. "finely diced"
      "isOptional": false                   // required
    }
  ],
  "isFavorite": false,                      // required
  "imageDataBase64": null                   // optional; omit for repo recipes
}
```

### Field notes

- **`prepTimeMinutes` / `cookTimeMinutes`**: use `0` to mean "not set". Any positive value is treated as the time in minutes.
- **`unit`**: must match a `MeasurementUnit` raw value. Valid values: `gram`, `kilogram`, `milliliter`, `liter`, `cup`, `tablespoon`, `teaspoon`, `piece`, `slice`, `clove`, `bunch`, `pinch`, `toTaste`. Unknown values fall back to `gram` on import.
- **`suggestedArchetypes`**: must match `ArchetypeType` raw values. Unknown values are silently dropped.
- **`imageDataBase64`**: **omit for repo recipes.** Base64-encoded images bloat JSON files and pollute diffs. Prefer `sourceURL` pointing to a public image, or no image at all.

## Contribution flow

1. Draft a recipe (with Claude's help if useful)
2. Save as `Recipes/<category>/<kebab-case-name>.json`
3. Verify it's valid JSON
4. Commit with a message like `chore: add lemon chicken pasta to curated recipes #24`
5. To use it: import via Settings as described above
