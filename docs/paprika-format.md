# Paprika Recipe Format Specification

Reference documentation for importing/exporting recipes and for AI-assisted recipe generation.

## File Format

**Extension:** `.paprikarecipes`

**Structure:** ZIP archive containing one or more recipe files. Each entry is gzip-compressed JSON.

**Compression layers:**
1. Outer: ZIP container (deflate or stored)
2. Inner: Each recipe entry is gzip-compressed JSON

**Alternative formats accepted by the importer:**
- Raw gzip-compressed JSON (magic bytes `0x1f 0x8b`)
- Plain JSON (no compression)

## JSON Schema

All fields are optional except `name`.

```json
{
  "uid": "string",
  "name": "string (REQUIRED)",
  "ingredients": "string (newline-separated)",
  "directions": "string (newline-separated)",
  "servings": "string",
  "prep_time": "string",
  "cook_time": "string",
  "notes": "string",
  "description": "string",
  "source": "string",
  "source_url": "string (URL)",
  "photo_data": "string (base64-encoded image)",
  "on_favorites": 0,
  "categories": ["string"],
  "rating": 0,
  "difficulty": "string",
  "nutritional_info": "string"
}
```

## Field Details

### name (REQUIRED)

The recipe title. Recipes with empty or missing names are skipped during import.

### ingredients

Newline-separated ingredient lines. Each line is parsed into structured data:

**Format:** `[quantity] [unit] ingredient name[, preparation note]`

**Examples:**
```
400g spaghetti
200g pancetta, diced
4 eggs
1 1/2 cups flour
1/2 tsp salt
2 cloves garlic, minced
1 bunch spring onions, sliced
Salt and black pepper, to taste
```

**Quantity parsing:**
- Integers: `2` → 2.0
- Decimals: `2.5` → 2.5
- Fractions: `1/2` → 0.5
- Mixed: `1 1/2` → 1.5
- Missing: defaults to 1.0

**Unit parsing (case-insensitive):**

| Input variants | Mapped unit |
|----------------|-------------|
| g, gm, gms, gram, grams | gram |
| kg, kgs, kilogram, kilograms | kilogram |
| ml, mls, milliliter, milliliters, millilitre, millilitres | milliliter |
| l, lt, lts, liter, liters, litre, litres | liter |
| cup, cups | cup |
| tbsp, tbs, tbsps, tablespoon, tablespoons | tablespoon |
| tsp, tsps, teaspoon, teaspoons | teaspoon |
| pc, pcs, piece, pieces | piece |
| slice, slices | slice |
| clove, cloves | clove |
| bunch, bunches | bunch |
| pinch, pinches | pinch |
| (no match) | piece (default) |

**Preparation note:** Text after the last comma is extracted as a preparation note (e.g. "diced", "minced", "grated", "to taste").

### directions

Newline-separated instruction steps. Each non-empty line becomes one step in the recipe's instruction list, preserving order.

**Example:**
```
Boil a large pot of salted water and cook pasta until al dente.
Fry pancetta in a large pan over medium heat until crispy.
Beat eggs with grated parmesan in a bowl.
Drain pasta, reserving 1 cup of cooking water.
Add pasta to the pancetta pan, remove from heat.
Pour egg mixture over pasta and toss quickly.
Add cooking water as needed for a creamy sauce.
Season with black pepper and serve immediately.
```

### servings

A string parsed for the first integer. Default is 4.

| Input | Parsed |
|-------|--------|
| `"4"` | 4 |
| `"4-6"` | 4 |
| `"Serves 4"` | 4 |
| `""` | 4 (default) |

### prep_time / cook_time

Duration strings parsed into minutes.

| Input | Parsed |
|-------|--------|
| `"25 min"` | 25 |
| `"1 hr 30 min"` | 90 |
| `"1 hr"` | 60 |
| `"45"` | 45 |
| `""` | nil |

**Recognised patterns:**
- Hours: `(\d+)\s*(?:hr|hour|hrs|hours)`
- Minutes: `(\d+)\s*(?:min|minute|minutes|mins)`
- Plain integer interpreted as minutes

### notes / description

Free text used as the recipe summary. `notes` takes priority; `description` is the fallback.

### source_url

URL string for the recipe's origin. Must be a valid URL to be stored.

### photo_data

Base64-encoded image data (JPEG or PNG). Decoded and stored as external binary data on the Recipe.

### on_favorites

Integer flag. `0` = not favourite, any non-zero value = favourite.

### categories

Array of strings used as recipe tags. Lowercased during import.

**Example:** `["Italian", "Pasta", "Quick"]` → stored as `["italian", "pasta", "quick"]`

### Fields Ignored by Import

| Field | Reason |
|-------|--------|
| `uid` | Internal Paprika identifier, not needed |
| `source` | Text source description, not stored |
| `nutritional_info` | Nutrition calculated from ingredients instead |
| `rating` | Not part of the data model |
| `difficulty` | Not part of the data model |

## Complete Example

```json
{
  "name": "Spaghetti Carbonara",
  "ingredients": "400g spaghetti\n200g pancetta, diced\n4 eggs\n100g parmesan cheese, grated\nSalt and black pepper, to taste",
  "directions": "Boil a large pot of salted water and cook spaghetti until al dente.\nFry pancetta in a large pan over medium heat until crispy and golden.\nBeat eggs with grated parmesan in a bowl until combined.\nDrain pasta, reserving a cup of cooking water.\nAdd hot pasta to the pancetta pan and remove from heat.\nPour the egg and cheese mixture over the pasta and toss quickly.\nAdd cooking water a splash at a time until you have a creamy sauce.\nSeason generously with black pepper and serve immediately.",
  "servings": "4",
  "prep_time": "10 min",
  "cook_time": "20 min",
  "notes": "A classic Roman pasta dish. The key is to remove the pan from heat before adding the egg mixture to avoid scrambling.",
  "source_url": "https://example.com/carbonara",
  "on_favorites": 1,
  "categories": ["Italian", "Pasta", "Quick Weeknight"]
}
```

**Import result:**
- **Recipe:** title="Spaghetti Carbonara", servings=4, prepTime=10, cookTime=20, isFavorite=true, tags=["italian", "pasta", "quick weeknight"]
- **Ingredients:** 5 entries preserving order, with preparation notes extracted from commas

## Generating Recipes for Import

When creating recipes (e.g. with Claude) for import into TableTogether:

1. Use the JSON schema above
2. `name` is required — everything else is optional but `ingredients`, `directions`, `servings`, `prep_time`, `cook_time`, and `categories` are strongly recommended
3. Format `ingredients` as newline-separated lines with `quantity unit name, prep note`
4. Format `directions` as newline-separated steps
5. Use recognised unit abbreviations (g, kg, ml, cup, tbsp, tsp, etc.)
6. Keep `categories` relevant for filtering: cuisine type, meal type, cooking style
7. Omit `photo_data` unless you have actual image data
8. Store as plain JSON files — the importer handles both plain JSON and gzip/ZIP formats
