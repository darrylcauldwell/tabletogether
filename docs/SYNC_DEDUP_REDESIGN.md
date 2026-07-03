# Sync Dedup Redesign — Design Brief

Status: DECIDED 2026-07-03 — Direction D (A+C), fix foundations now. Design and
implementation order in "Decided design" below. Commits reference `#ChangeN`.
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

## Open questions — ANSWERED (user, 2026-07-03)

1. Sequencing: **pause sharing validation until the redesign lands.** Both apps
   stay quit; no stopgap. Wife acceptance test resumes on the fixed build.
2. Empty slots: **no product reason to exist as data — UI affordances only.**
   Direction C is unblocked.
3. Appetite: **fix foundations now** while all data is dev-only. Full Direction D.

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

---

# Decided design (2026-07-03)

IMPLEMENTATION STATUS (2026-07-03): Changes 1–5 landed (commits 936b3a4, 9d9c3da,
47512c0, f55d4cb, e4a1b77). Preflight passes on iOS/Catalyst/tvOS with 279 unit
tests; the only failing gate is the pre-existing CloudKit Dashboard schema deploy
(see PRODUCTION_READINESS_2026-07.md). Simulator verification: fresh launch seeds
no plans/slots, planner renders the virtual week, offline (no iCloud) path works.
Change 6 (Mac + iPhone soak, then the acceptance test) awaits the user — both
devices MUST be updated to this build before either app is relaunched.

Direction D. Two pillars: a **correct dedup engine** (Apple's sanctioned convergence
mechanism — non-optional even with lazy creation, because offline concurrent creation
can always collide) and **lazy structure** (slots and week plans exist only when a
meal is planned, removing ~all systemic duplicate pressure). No Core Data model
changes — nothing added to the pending CloudKit schema deploy.

## Change 1 — Dedup engine rewrite (`PersistenceController`)

Rewrite `deduplicateIfNeeded` (currently `PersistenceController.swift:699`) around
three fixes, in this order per duplicate group:

### 1a. Winner selection: CKRecord name ascending, with a deferral rule

Winner = candidate with the lexicographically smallest CKRecord `recordName`, via
`container.recordID(for: objectID)`. Record names are identical on every device
(mirrors Apple's uuid-ascending sample; our `id` attribute can't tie-break because
duplicates share it by construction).

**Deferral rule (critical):** `recordID(for:)` returns nil for a locally created
record that has not yet exported. Any preference between a nil and non-nil candidate
is device-DEPENDENT — e.g. "exported beats unexported" makes each device delete its
own copy, so both copies die. Therefore: if ANY candidate in a group lacks a record
ID, **skip the group this round** and remember it. Retry deferred groups on the next
history-processing batch and on the next successful `.export` CloudKit event.
Convergence is still guaranteed: once both copies have exported, whichever device
imports last sees both record names and applies the deterministic rule; its deletion
syncs to the other device. Deletes are idempotent across devices.

### 1b. Zone scoping

Group candidates by `recordID.zoneID` and dedup only within a zone (Apple's sharing
sample does this). This matters on the OWNER's device: once the household is shared,
shared objects live in a share zone inside the private database, so a private-store
fetch can span zones. Cross-zone same-id rows are NOT duplicates. Keep the existing
private-store-only trigger and `affectedStores` scoping unchanged.

### 1c. Re-point, merge, then delete

Per group: winner from 1a; **freshest** = candidate with max `modifiedAt` (fall back
`createdAt`, else the winner). Then:

1. **Adopt (LWW entities only)** — if freshest ≠ winner, copy freshest's user
   attributes onto winner (`modifiedAt` = max of group; keep winner's `id`,
   earliest `createdAt`) and REPLACE the winner's "owned" relationships with
   freshest's (re-pointing freshest's cascade children to winner BEFORE any delete,
   so the cascade can't kill them):
   - `MealSlot`: adopt `recipes`, `components`, `archetype`, `modifiedBy`,
     `assignedTo` + all user attributes (`customMealName`, `servingsPlanned`,
     `notes`, `isSkipped`). A meal is one coherent plate — union would mix two
     meals; LWW takes the newest wholesale.
   - `Recipe`: adopt `recipeIngredients` + attributes.
   - `WeekPlan`, `Ingredient`: attributes only (children are unioned, below).
2. **Union re-point (all entities)** — for every other to-many relationship on each
   loser, move members to the winner (Apple's `removeFromTags`/`addToTags` pattern).
   This kills the cascade annihilation: `WeekPlan→slots`, `WeekPlan→groceryItems`
   survive on the winner. Re-pointed same-identity slots become a MealSlot duplicate
   group that this same engine collapses. Relationships in an entity's adopt list
   are exempt for stale losers — their cascade children die with them (correct: they
   are the losing version's plate).
3. **Delete losers.**

Entity classes: LWW user-edited (`Recipe`, `Ingredient`, `MealSlot`, `WeekPlan` —
reliable `modifiedAt`) get adopt+union; structural/system (`Household`, `User`,
`MealArchetype`, `GroceryItem`, `FoodItem`, `RecipeIngredient`, `SuggestionMemory`)
get union re-pointing only, winner keeps its attributes.

### 1d. Launch sweep

History-insert triggering misses opportunities (app killed mid-cycle, deferred
groups). Add a one-shot sweep on launch: for each deterministic-id entity, fetch
groups with duplicate `id` in the private store and run the same engine. Cheap when
clean; self-healing when not.

### 1e. Testability

Extract winner selection and merge into pure functions taking
`(candidates, recordNamesByObjectID)` so tests inject record names without CloudKit.
Required tests: (1) winner is device-independent — same result for any candidate
ordering; (2) nil record ID defers, never deletes; (3) WeekPlan dedup preserves all
slots on the winner (no annihilation); (4) newest `customMealName` survives MealSlot
dedup (no edit loss); (5) adopt re-points freshest's components before delete;
(6) cross-zone same-id rows untouched.

## Change 2 — Lazy slot & plan creation

Helpers (deterministic IDs make concurrent creation converge; residual same-slot
collisions are exactly what Change 1 resolves):

- `WeekPlan.fetchOrCreate(for: weekStartDate, household:, in: context)` — fetch by
  deterministic id in the private store, create if absent. NO `createDefaultSlots`.
- `WeekPlan.fetchOrCreateSlot(day:mealType:in:)` — fetch by (day, mealType), create
  with `MealSlot.deterministicID` if absent.

Consumers (the four "breaks" from the blast-radius audit):

- `WeekListView.addMealButton` (`WeekListView.swift:165`): replace the
  `guard ... else { return }` no-op with `fetchOrCreateSlot`.
- `DayColumnView` empty cells: placeholder becomes interactive (tap → same add-meal
  path) and a drop target; drop/tap materializes the slot on demand.
- `WeekPlan.copyFrom` (`WeekPlan+CoreData.swift:156`): iterate source slots that
  carry content (planned or custom-named); `fetchOrCreateSlot` the destination
  instead of silently dropping. Do NOT copy `isSkipped`-only slots (skips are
  week-specific) and do not materialize empties.
- `WeekPlannerView.ensureWeekPlanExists` (`WeekPlannerView.swift:120`): views render
  a virtual 7×4 grid from an OPTIONAL plan; the plan itself is created on first
  write (plan a meal, set a note, copy-week, generate groceries), not on navigation.
  Navigating weeks creates nothing.

## Change 3 — Virtual-grid metrics

OUTCOME (2026-07-03): implementation found `planningProgress`, `activeSlotsCount`,
`plannedMealsCount`, and `emptySlots` had NO consumers anywhere (app, tvOS, tests)
— deleted rather than rewritten, with a source comment requiring any future
progress metric to use the virtual grid (7 × defaultPlannedMeals) as denominator,
never `slotsArray.count`. The `DayColumnView` blast-radius item was also dead
code: `WeekGridView`/`DayByDayView`/`DayTabButton` (replaced by `WeekListView`)
and their private children `DayColumnView`/`MealSlotView` were deleted. All other
consumers already filter on `isPlanned`/non-empty (verified in blast-radius audit).

## Change 4 — Remove seeding & self-heal

In `TableTogetherApp.initializeDataIfNeeded` (`TableTogetherApp.swift:115-151`):
delete the WeekPlan existence check, creation branch, `createDefaultSlots` call, and
the entire self-heal block (commit 4d0b635 — it feeds the thrash loop). KEEP
Household, User, and archetype seeding — small fixed set, residual duplicates are
exactly what the Change 1 engine now handles correctly. `createDefaultSlots` itself
is deleted once no callers remain (demo/screenshot seeders may keep a local variant).

Ordering constraint: Changes 2–3 land BEFORE this one so the UI never sees a
slotless week it can't act on.

## Change 5 — One-time empty-structure cleanup

Existing stores hold pre-materialized empty slots (Mac: 25). Code from Changes 2–4
must tolerate them regardless (the other device creates them until updated), so this
is hygiene, not correctness: one-shot per device (UserDefaults flag), private store
only — delete every MealSlot where `isEmpty && !isSkipped && notes == nil`, then
every WeekPlan with no slots, nil `householdNote`, and no grocery items. Both
devices deleting the same records is idempotent. No store wipe — preserves the
existing share and its URL.

## Change 6 — Sync soak, then resume acceptance test

1. Build and install the fixed build on BOTH devices before relaunching either
   (relaunching one old build resumes the thrash).
2. Soak: run Mac + iPhone concurrently ≥30 min; plan/edit/clear meals on both,
   including a deliberate same-slot concurrent edit. Pass = slot counts stable
   across sync cycles, no `Deduplicated CloudKit records` churn loop in logs, edits
   survive on both sides, LWW picks the newer edit.
3. Only then: wife's acceptance test via the existing share URL.

## Acceptance criteria (map to the three live failures)

1. **No annihilation**: concurrent-seeded WeekPlans converge to one plan holding
   every planned slot; grocery items survive dedup.
2. **No edit loss**: an attribute edit on any duplicate copy survives; newest wins.
3. **No thrash**: both devices select the same winner; slot/record counts are stable
   under repeated sync cycles with both apps running.
4. Add-meal and drag-drop work on any cell of any week with zero pre-existing slots.
5. Copy-week carries all content into a virgin destination week.
6. No code path bulk-creates 28 slots; navigating weeks writes nothing.
7. Progress metrics correct for nil plan, empty plan, and partially planned weeks.
8. Shared store is never deduplicated; same-id rows in different zones untouched.
