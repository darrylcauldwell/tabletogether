# Sync Dedup Redesign — Design Brief

Status: DECISION PENDING. This document is the anchor for a fresh design session.
Written 2026-07-03 after live failures on 2026-07-02 evening. Companion spec:
`PRODUCTION_READINESS_2026-07.md`.

## Problem statement

Every device seeds system entities at launch (Household, User "Me", MealArchetypes,
current WeekPlan + 28 empty MealSlots) using deterministic UUID *attributes*
(`UUID.deterministic(from:)`, SHA-256 of a stable string). But
NSPersistentCloudKitContainer identity is the **CKRecord**, not the `id` attribute —
concurrent seeding creates duplicate CKRecords that a custom
`deduplicateIfNeeded` engine (PersistenceController) collapses after import.

### Live failures observed 2026-07-02 (dev environment, Mac + iPhone, same Apple ID)

1. **Slot annihilation**: dedup deleted a duplicate WeekPlan; `WeekPlan→slots` is
   Cascade and no children are re-pointed first, so the surviving plan lost all its
   slots (28 → 0). "Add meal" silently no-ops on a slotless plan
   (`WeekListView.addMealButton` guard).
2. **Edit destruction**: user set `customMealName = "Chips"` on a slot copy that
   dedup then deleted; the engine does no attribute merging, so the edit vanished.
3. **Cross-device thrash**: winner = lexicographically smallest
   `objectID.uriRepresentation()` — a **device-local** key. Two devices pick
   different winners and delete each other's keepers; observed 28 → 25 slots and
   falling until both apps were quit. The slot self-heal (commit 4d0b635) recreates
   slots on both devices and thereby *feeds* the loop.

## Constraints

- Offline-first: never block editing (or first launch) on network availability.
- CloudKit private + shared store pair; dedup currently runs only on the private store.
- Product spec: quiet last-write-wins conflict resolution; no roles; calm UX.
- Losing a family member's edits is unacceptable.
- All data is currently dev-environment-only; migration cost is at its lifetime minimum.

## Codebase facts (verified 2026-07-02, file:line in repo at commit 22a013c)

### Deterministic ID scheme
- `UUID.deterministic(from:)` — SHA-256 → UUID (`UUID+Deterministic.swift:13`)
- Household.defaultID = `…0001`; User provisional = `…0002` (per-account real ID via
  `UserIdentity.deterministicID(fromRecordName:)` since commit c7eeeda)
- `MealArchetype`: `"archetype:<rawValue>"`; `WeekPlan`: `"weekplan:<isoWeekKey>"`;
  `MealSlot`: `"mealslot:<isoWeekKey>:<day>:<mealType>"` — slot identity is a pure
  function of (week, day, mealType), which makes lazy creation converge.

### Seeding sites
- `TableTogetherApp.initializeDataIfNeeded` (App bootstrap): Household (with
  private-store-scoped merge + orphan re-parenting), system archetypes, current-week
  WeekPlan + `createDefaultSlots` (28 = 7 days × 4 meal types), **self-heal of
  missing slots** (4d0b635 — to be removed/rethought by this redesign).
- `ContentView.ensureUserExists` (after `UserIdentity.resolveIfNeeded`).
- `WeekPlannerView.ensureWeekPlanExists`: creates ANY navigated-to week + 28 slots
  on demand (this is how future weeks materialize; no scheduled job).
- Demo/tvOS seeders are screenshot-mode only; tvOS has no production seeding.

### Slot consumers — lazy-creation blast radius
Breaks (4): `WeekListView.addMealButton` (guard returns if slot missing — must
create-on-demand); `DayColumnView` empty cells (placeholder exists but is
non-interactive and not a drop target); `WeekPlan.copyFrom` (copies only into
existing destination slots — silently drops otherwise); the self-heal loop
(inverts the invariant; must go).
Semantics change (2): `planningProgress` / `activeSlotsCount` use
`slotsArray.count` as denominator — must switch to a virtual 28-cell grid.
Safe (everything else): grocery generation, CalendarService export, SuggestionEngine,
PrivateDataManager.syncPlannedMeals, QuickLogSheet, WeekPlannedNutritionCard, tvOS
views, clearAll, deep links — all filter on `isPlanned`/non-empty recipes.

### Dedup engine (`PersistenceController.deduplicateIfNeeded`)
- Trigger: persistent-history processing, `.insert` changes only, private store only,
  fetch scoped `affectedStores = [store]`.
- 11 entities: Household, Recipe, Ingredient, User, WeekPlan, MealSlot,
  MealArchetype, GroceryItem, FoodItem, RecipeIngredient, SuggestionMemory
  (NOT MealSlotComponent).
- Defects: (1) arbitrary device-local winner; (2) no relationship re-pointing before
  delete; (3) no attribute merge.

### Cascade edges that make blind dedup destructive
`WeekPlan→slots`, `WeekPlan→groceryItems`, `MealSlot→components`,
`Recipe→recipeIngredients`. All other relationships among deduped entities are
Nullify (orphaning, not deletion). Household children are all Nullify (the app-level
`ensureHousehold` merge re-points manually; the dedup engine does not).

### Last-write-wins feasibility
`modifiedAt` present and reliably bumped: Recipe, Ingredient, MealSlot, WeekPlan
(the user-edited entities). `createdAt` only: Household, User, FoodItem, GroceryItem.
Neither: MealArchetype, RecipeIngredient, SuggestionMemory (system/structural — for
these, merging matters less than re-pointing).

## Candidate directions

- **A. Fix dedup in place**: deterministic cross-device winner (modifiedAt desc,
  then a device-independent tiebreak — candidate: CKRecord recordName via
  `container.record(for:)`); re-point relationships from losers to winner before
  deleting; merge attributes for LWW entities; orphan-avoidance for cascade parents.
- **B. Gate seeding on first import**: only seed after initial CloudKit import
  completes (or account is verifiably empty); shrinks but does not eliminate the
  duplicate window (offline-first means seeding can't wait forever).
- **C. Lazy structure**: stop materializing empty WeekPlans/slots; create a slot
  only when a meal is planned into it (deterministic IDs make concurrent creation
  converge to rare same-slot conflicts, resolved by LWW). Empty cells become UI
  affordances. Eliminates the bulk duplicate mass and the need for self-heal.
- **D. Combinations** — likely A+C: lazy structure removes the systemic duplicate
  pressure; a smaller, correct dedup engine handles residual genuine collisions
  (Household, User, same-slot concurrent creation).

## Open questions (user)

1. Finish the two-person sharing validation on a contained stopgap first, or pause
   until the redesign lands?
2. Any product reason for empty slots to exist as data rather than UI?
3. Appetite: minimal-change-then-ship vs fix-foundations-now (data is dev-only).

## Apple guidance research (completed 2026-07-03, primary sources read)

From Apple's CoreDataCloudKitDemo (WWDC19) and CoreDataCloudKitShare (WWDC21)
samples (code verified via mirrors ralfebert/SynchronizingALocalStoreToTheCloud and
delawaremathguy/CoreDataCloudKitShare):

- **Winner selection**: duplicates (Tags, matched by `name`) sorted by `uuid`
  ascending; first wins. Sample comment: "All peers should eventually reach the same
  result with no coordination or communication." Deterministic + device-independent
  is the load-bearing property. NOTE for TableTogether: our duplicates share the
  SAME deterministic `id`, so the stable tiebreak must come from elsewhere — the
  CKRecord name via `container.recordID(for: objectID)` (identical on every device)
  is the Apple-shaped choice.
- **Re-pointing before deletion**: yes — each loser's relationships are moved to the
  winner (`photo.removeFromTags(tag); photo.addToTags(winner)`) in the same save,
  then the loser is deleted. Apple does NOT merge attribute values (community
  practice adds merge-before-delete for settings-like records; we need it for LWW
  on user-edited entities: winner keeps stable identity, then fold in the
  newest-`modifiedAt` copy's attribute values).
- **Owner-only dedup** (sharing sample): history processing bails unless the store
  is the private store — only owners dedupe; participants never do. TableTogether
  already scopes dedup to the private store ✓.
- **Zone scoping** (sharing sample): candidates filtered to the same CloudKit zone
  via `persistentContainer.recordID(for:)`.
- **No singleton-record pattern exists** for NSPersistentCloudKitContainer; you
  cannot choose CKRecord IDs. Deterministic dedup after import IS Apple's sanctioned
  convergence mechanism for seeded/default data (WWDC19 explicitly frames dedup as
  the answer to per-device seeding).
- **Lazy creation** is community-endorsed to shrink the duplicate window but cannot
  eliminate it (offline concurrent creation) — dedup correctness is required either
  way. Sources: developer.apple.com/forums/thread/699634,
  github.com/vichudson1/DeDuplicatingEntity.

### Synthesis (for the design session)

Direction D (A+C) is validated: a correct dedup engine is non-optional (Apple's
answer to seeding), and lazy slot creation removes ~all systemic duplicate pressure
so the engine handles only rare genuine collisions. Dedup fix shape: winner by
CKRecord-name ascending (stable across devices, mirrors Apple); re-point ALL loser
relationships to winner pre-delete (kills the cascade annihilation); attribute-merge
from the newest-`modifiedAt` duplicate for LWW entities (kills edit loss); keep
private-store-only scoping.

## Current device/environment state (2026-07-03 morning)

- Both apps QUIT; must stay quit until a fix lands (running both resumes the thrash).
- Mac store: 1 WeekPlan, 25 slots (3 annihilated), 0 custom names, 226 recipes,
  1 correct per-account User. iPhone state unknown but similar.
- Dev CloudKit schema: `MealLog`/`PersonalSettings` record types still absent until
  first write (see PRODUCTION_READINESS spec, blocker table note).
- Wife's acceptance test still pending; share exists with URL (link-joining enabled).
