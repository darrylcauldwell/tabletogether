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

## Layout

This directory is **flat** — no subfolders. Categorisation lives in each recipe's `tags` field, not in the folder structure. A single recipe can carry as many tags as suits it (e.g. `["indian", "vegetarian", "weeknight"]`).

The default file is `recipes.json` — one big JSON array containing every curated recipe. Importing it brings the whole library in one tap.

### File format flexibility

The importer accepts either shape, so you can split things up if you ever want to:

- **A JSON array** (`[ {recipe1}, {recipe2}, ... ]`) — used by `recipes.json`
- **A single JSON object** (`{recipe}`) — useful for sharing or testing one recipe at a time

Both produce the same result — the importer detects which shape it's reading.

## File format

Each recipe matches the `CodableRecipe` schema used by the app's existing Export feature, so any recipe exported from TableTogether is a valid curated recipe.

### Schema

```jsonc
{
  "title": "Lemon Chicken Pasta",          // required
  "summary": "A bright, 20-minute dinner.", // optional
  "sourceURL": "https://example.com/...",   // optional
  "cookbook": "Curry Easy",                 // optional — cookbook of origin
  "imageURL": "https://example.com/thumb.jpg", // optional — remote thumbnail URL
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

- **`cookbook`**: optional. The cookbook the recipe was originally published in (e.g. `"Curry Easy"`, `"Rick Stein's Secret France"`). Useful for provenance and for grouping by source. Leave `null` or omit if not applicable.
- **`imageURL`**: optional. A remote thumbnail URL the app can fetch lazily on first display. Prefer this over `imageDataBase64` for repo recipes — URLs add only a few bytes per recipe instead of bloating the JSON with base64-encoded image data. Leave `null` or omit if no remote image is available.
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
