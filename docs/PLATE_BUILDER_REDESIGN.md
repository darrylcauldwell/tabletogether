# Plate Builder — meal-slot plate unification (corrected design)

Goal: let a planned meal hold a **main dish + sides** (e.g. lentil dhal + naan +
rice + veg) with aggregated per-serving macros, built in the meal editor.

The plate is modelled by `MealSlotComponent` (kinds: recipe / ingredient /
foodItem). Today the planner writes the **legacy `recipes` relationship** and the
component model is unused in production. This redesign moves the planner to
components — **safely**, without the sync catastrophe the first design hit.

## Why the "obvious" design is wrong (adversarial findings, 2026-07-04)

A first design (transient synthesis + one-shot launch backfill that clears
`recipes`, relying on deterministic component ids to converge) was demolished on
all five verification angles:

1. **Sync FATAL.** `MealSlotComponent` is **excluded from `DeduplicationEngine`**
   (`DeduplicationEngine.swift:26-31`, deliberate: "random ids, owned via
   adoption"). NSPersistentCloudKitContainer keys CKRecords by internal
   recordName, not the `id` attribute — same-`id` rows only collapse if the dedup
   engine processes them, and it never processes components. So a per-device
   launch backfill creates **duplicate component rows on every device** →
   `plannedMacros` and grocery **double** household-wide. Deterministic ids are
   decorative for this entity.
2. **Transient synthesis crashes.** Synthesising a `MealSlotComponent(insertInto:
   nil)` and setting `.recipe` mutates the persisted `Recipe`'s inverse across a
   nil/foreign context — "different contexts" UB/crash.
3. **Macro drop.** Authoritative-stored silently suppresses any `recipes` write
   that arrives after migration (old client / merge) with no matching component.
4. **Planned-log undercounts.** `plannedLog` seeds one `recipeID`; a multi-item
   plate logs only the first recipe — sides vanish from personal Insights.
   Side-only plates seed a phantom anonymous 0-kcal entry.
5. **Grocery gaps.** Typed sides routed to `.foodItem` emit no grocery line;
   ingredient sides don't scale by `servingsPlanned`.

## Corrected architecture: reconciling reads, migrate-on-touch, no backfill

**Reads — one reconciling accessor, value structs (no managed objects):**
`MealSlot.plateItems: [PlateItem]` where `PlateItem` is a plain value struct
(kind, displayName, refs to recipe/ingredient/foodItem, portionScale/quantity/
unit, and `macrosForOneSlotServing`). Computed as:
- Map `storedComponents` → `PlateItem`, **deduped by identity key** (recipe.id /
  ingredient.id / foodItem.id), keeping the lowest `order`.
- **Union** in any legacy `recipesArray` recipe whose id is *not already*
  represented by a recipe component (portionScale 1.0, order after components).

This is **authoritative-but-reconciling**: no drop (un-migrated/merged legacy
recipes still counted), no double-count (dedup by entity id — even if two devices
created duplicate component rows, reads collapse them), and **no transient
managed objects** (structs dodge the inverse crash).

`plannedMacros` = Σ `plateItems.macrosForOneSlotServing` × `servingsPlanned`.
`isPlanned` / `isEmpty` / `displayTitle` / `WeekPlan.uniqueRecipes` all read
`plateItems`.

**Writes — components only, migrate the touched slot, never a global sweep:**
- `addRecipe` / `addSide(ingredient|foodItem)`: `ensureComponentsMigrated()`
  first (convert this slot's legacy recipes → recipe components, then clear
  **this slot's** `recipes`), then append the new component. **One-entity-per-slot
  invariant:** if a component of the same kind+entity already exists, update its
  portionScale/quantity in place instead of appending a second row (reads dedup
  by entity id, so a second same-entity row would be silently dropped).
- `removeItem`: migrate all recipes **except** the one being removed (never
  create-then-delete → no CloudKit delete-vs-recreate resurrection).
- `setCustomMeal` / `skip` / `clear`: delete components **and** clear `recipes`
  (these are genuine non-recipe overwrites, so old-client visibility of the old
  recipes is correctly dropped).
- `copyFrom`: **keep** `matchingSlot.recipes = otherSlot.recipes` (preserves
  old-client visibility of copied recipe plates) **and additionally** write
  components for non-recipe sides. Read-side dedup unions legacy recipes only
  when not already represented by a component, so this never double-counts on
  new clients. In `copyComponents`, **diff** against existing destination
  components by (kind, entityID) — update-in-place / add-missing / remove-gone —
  rather than delete-then-recreate (MealSlotComponent is dedup-excluded, so
  delete-then-recreate risks CloudKit resurrection/bloat). Use deterministic ids
  `component:<destSlotID>:<kind>:<entityID>` for added components (identity =
  slot+entity, NOT order).

**No `PlateMigrationService`, no launch backfill, no global `recipes` clear.**
Untouched legacy slots read correctly via reconciliation forever. This removes
the multi-device mass-duplication hazard at its root and eliminates the
old-client cutover risk entirely (old clients keep seeing `recipes`; new clients
reconcile). Migrate-on-touch is a single-device interactive act; the rare
two-people-edit-same-slot race is absorbed by read-side dedup.

**Planned-log (`PrivateDataManager.plannedLog`)** — reads `slot.plateItems`, not
`recipesArray` (which is empty after migrate-on-touch → would seed a phantom):
- Single recipe item, no sides → keep the recipeID fast-path (existing behaviour;
  Insights derives macros from the recipe × servingsConsumed).
- >1 item OR any non-recipe component → `recipeID = nil`, `quickLogName` from
  joined `plateItems.displayName`, and **per-person macros =
  Σ `plateItems.macrosForOneSlotServing` × `perPersonServings`** — NOT
  `plannedMacros` (which already includes `× servingsPlanned` = whole-plate
  total; feeding it would 2–4× the person's Insights). Setting `recipeID = nil`
  keeps the branches mutually exclusive and avoids the MacroAggregator-vs-card
  gating divergence. No phantom 0-kcal entries.

**Grocery — two different scaling bases (this is the subtle one):**
- Recipe MACROS are *per-serving* → `× servingsPlanned × portionScale`, no divisor.
- Recipe INGREDIENTS are *per-full-recipe* → `quantity × (servingsPlanned /
  max(recipe.servings,1)) × portionScale` (i.e. `ri.scaledQuantity(originalServings:
  recipe.servings, newServings: servingsPlanned) × portionScale`). **Both current
  generators already apply the `/recipe.servings` divisor — do NOT drop it, or a
  4-serving recipe for 4 people quadruples the list.**
- Ingredient side lines → `× servingsPlanned`, merged with recipe-derived
  duplicates by normalised (ingredient.id, unit).
- FoodItem components → a name-only line (so typed sides still reach shopping).
- Type-and-resolve sides attach as **ingredient** components where possible so
  they always emit a grocery line; offline, fall back to the library pickers.
- `PantryCheckView.hasPlannedRecipes` / `generateForNewPlans` guards must move off
  raw `recipesArray` to `isPlanned`/`plateItems` so component-only slots generate.

**tvOS is a consumer too.** `AmbientView.swift` and `TVMealCard.swift` read
`slot.recipesArray` directly — under migrate-on-touch an edited slot's recipes is
cleared, so they must read the reconciling `plateItems` (or at minimum
storedComponents-with-recipesArray fallback) or the ambient whiteboard blanks
every edited meal.

## Product decisions (defaults chosen per spec; flag if you disagree)
- Portion control: discrete steps (½ / 1 / 1½ / 2) — calmer, matches restraint.
- FoodItem sides emit a name-only grocery reminder (not silent).
- Typed sides resolve to ingredient components when possible for grocery.
- Multi-item plates seed the personal log from aggregated plannedMacros.

## Staging (each independently shippable, app fully working, tests green)
1. `PlateItem` struct + reconciling `plateItems` (dedup-by-entity + union un-represented legacy recipes) + `plannedMacros`/`isPlanned`/`isEmpty`/`displayTitle` on it. Pure read refactor. Test: legacy-only == component-only == mixed give same macros; duplicate component rows don't double-count.
2. Route ALL consumers through `plateItems`: grocery ×2 (with the correct `/recipe.servings` divisor), `WeekPlan.uniqueRecipes`, `CalendarService`, `SuggestionEngine`, `PrivateDataManager.plannedLog` (per-person = per-serving-sum × perPersonServings, recipeID=nil for multi-item), `QuickLogSheet`, `WeekListView`/`MealSlotComponents` resolvedNames (UNION not either/or), `PantryCheckView` guards, **and tvOS `AmbientView`/`TVMealCard`**. Equivalence-tested vs legacy. Read-only.
3. Write paths: `ensureComponentsMigrated` (per-slot, clears own recipes); addRecipe/addSide with one-entity-per-slot merge; removeItem (migrate-all-except-removed); custom/skip/clear delete components + clear recipes; `copyFrom` keeps `recipes`, diffs components in place, deterministic ids.
4. Plate-builder editor: dishes (recipe components, ½/1/1½/2 portion stepper) + custom-meal fallback (shown only when empty).
5. Sides: ingredient/foodItem components, SidePicker (library + type-and-resolve → ingredient component), grocery lines (× servingsPlanned, unit-normalised merge), demo data.

**Hard invariant (tested):** every consumer reads the deduped `plateItems` — never `storedComponents`/`recipesArray` directly. An equivalence test simulates duplicate component rows and asserts macros + grocery unchanged.

Residual accepted risks: cross-device portionScale tiebreak nondeterminism (LWW settles it); `PlateItem` is non-Sendable (view-context only); bounded component-row bloat under repeated concurrent copies (read-dedup keeps numbers correct).

No CloudKit schema change (CD_MealSlotComponent already in production).
