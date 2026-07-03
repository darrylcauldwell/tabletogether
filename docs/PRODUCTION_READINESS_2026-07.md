# Production Readiness Remediation — July 2026

Findings from the 2026-07-02 production-readiness assessment (preflight + code-quality,
release-readiness, and data-integrity audits). This spec drives the fixes; commits
reference the change numbers below.

## Self-report (sharing boundaries)

- **Shared:** Household, Recipes, MealSlots/WeekPlans, ingredients, grocery lists —
  CloudKit shared database, all participants equal, last write wins.
- **Personal:** consumption logs, portions, targets, insights — private database only,
  may reference shared meals by ID; shared data never references personal data.
- **Conflicts:** quiet last-write-wins; no history, no roles.
- **UX:** no judgment/comparison surfaces; sync-error surfacing (Change 2) must stay
  informational and calm — a quiet banner, not a warning state.
- **Platforms:** identity fix (Change 3) affects iOS/iPadOS/macOS private tracking;
  tvOS is read-mostly ambient and never shows personal data, so it is unaffected
  except for sharing the Core Data model.
- **Ambiguity:** migration of existing devices already holding the legacy shared
  "Me" UUID is the risky part of Change 3; design section below.

## Status of assessment blockers

| # | Blocker | Resolution |
|---|---------|------------|
| 1 | Flaky parser tests (Apple Intelligence nondeterminism) | Change 1 |
| 2 | Undeployed CloudKit schema (`Recipe.sourceUID`) | Manual: deploy Dev→Production in CloudKit Dashboard, then `scripts/mark-schema-deployed.sh`. **Before deploying, verify the hand-rolled record types `MealLog` and `PersonalSettings` exist in the dev schema** (they live outside the Core Data model, so the preflight hash gate cannot see them; they are only created by an actual write in dev — discovered 2026-07-02 when a dev-environment schema reset silently removed them and broke private-log fetches) |
| 3 | Privacy/support/marketing URLs 404 (private repo) | Done 2026-07-02: repo made public; all three URLs verified 200 |
| 4 | Shared `User.defaultMeID` misattributes private logs | Change 3 |

## Change 1 — Deterministic parser tests

`NaturalLanguageMealParser.parse` tries Apple Intelligence (`LanguageModelSession`)
before the regex fallback. Tests assert exact regex-path outputs, so results depend
on whether the on-device model responds in that run → flaky preflight.

- Add an `enableAppleIntelligence` flag (default `true`) to the parser initializer.
- Tests construct the parser with it disabled, pinning the deterministic regex path.
- Production call sites unchanged.

**Acceptance:** full test suite passes repeatedly; parser tests no longer depend on
Apple Intelligence availability.

## Change 2 — Surface sync errors to users

`PrivateDataManager` produces user-facing `SyncError` values but `SyncErrorBanner`
is never instantiated; non-retryable failures (iCloud quota, signed out) are
silent outside the CloudKit Diagnostics screen.

- Wire `SyncErrorBanner` into the personal-tracking surfaces (meal log / insights)
  where `PrivateDataManager` is already in the environment.
- Tone per UX guardrails: neutral, informational, dismissible; link to Settings →
  CloudKit Diagnostics for recovery. No red alarm states.

**Acceptance:** with a simulated `.notAuthenticated`/`.quotaExceeded` error, the
banner appears on personal surfaces and leads to diagnostics.

## Change 3 — Per-device user identity

All devices seed "Me" as `User.defaultMeID` (…0002). After a household is shared, a
participant's device holds two `User` rows with the same UUID (own + owner's mirror);
`User.current(in:)` can resolve to the wrong member and
`PrivateDataManager.syncPlannedMeals` seeds one member's planned meals into another
member's private log.

Design — identity is per Apple ID, derived from CloudKit (research findings:
`cloudKitRecordID` on User is currently dead/always-nil; private models never
reference the user; assignments are relationships, so an id rewrite is safe):

- **Identity derivation:** `meID = deterministicUUID(CKContainer.userRecordID
  .recordName)` (SHA-256 → first 16 bytes, UUID bits set). Same Apple ID on any
  device computes the same UUID with no coordination — preserving the multi-device
  convergence `defaultMeID` was introduced for — while different household members
  get distinct ids. Record name cached in UserDefaults alongside the resolved id.
- **Provisional state:** offline-first startup keeps seeding `defaultMeID`
  ("not yet identified"); identity upgrade runs when CloudKit becomes reachable.
  No behavior regression while offline versus today.
- **Migration (never guess):** if a User with `meID` exists → done. Else among
  `defaultMeID` rows: exactly one → rewrite its id to `meID`; several → prefer the
  single row in the private store (locally created); still ambiguous → create a
  fresh identified row and leave existing rows untouched (they may belong to other
  members). Set `cloudKitRecordID = recordName` on the adopted row.
- **Resolution:** `User.current(in:)` prefers the stored `meID`, falls back to
  `defaultMeID`, then first.
- No Core Data model change → no CloudKit schema deploy required.

**Acceptance:** two-device shared household — assignments on device A never appear
in device B's private log; same-Apple-ID devices converge on one User row;
existing single-device data survives upgrade; offline first launch still works.

## Change 4 — Documentation fix

`APP_STORE_CONNECT_SETUP.md` lists the tvOS bundle ID as
`dev.dreamfold.tabletogethertv`; actual is `dev.dreamfold.tabletogether.tv`.

## Change 5 — Share creation off the main actor (found in live testing 2026-07-02)

`CloudSharingView.prepareShare()` called `container.share(_:to:)` from the main
actor; Core Data blocks the calling thread while exporting the share zone
(`_PFRequestExecutor wait`), freezing the UI and risking deadlock with the
main-queue history merge. Fixed: share creation runs `nonisolated` on a
background context. Verified live: no beachball, share created and reused
correctly.

## Live sharing test log (2026-07-02 evening)

Verified on real hardware after a full dev-environment clean sheet (CloudKit
Console zone deletion + Reset All Sync Data on Mac and iPhone):
- Identity: fresh seed produced exactly one "Me" with the derived per-account ID
  on the Mac; iPhone converged with no duplicate user. Derivation independently
  recomputed and matched.
- Recipes: 226 imported on Mac from canonical `Recipes/recipes.json`, synced to
  iPhone (required a cold relaunch — dev push lag).
- Share: created cleanly from Mac after Change 5; single share zone; URL arrived
  via sync. Cross-member acceptance + private-log separation test PENDING (second
  household member).

## Deferred (tracked, not in this spec)

- Tests for dedup / store reset / sharing purge / PrivateDataManager offline paths
- Versioned Core Data model + migration test before next schema change
- `Household+Transferable` fatalError on malformed payload
- In-app prompt for orphaned private-zone recovery (beyond Change 2 banner)
- Reset All Sync Data leaves the app unseeded until relaunch — bootstrap
  (identity resolve + ensureUserExists + archetypes) should re-run post-reset
- Freshly created "Me" row only gets `cloudKitRecordID` annotated on next launch
- `UICloudSharingController` renders poorly under Mac Catalyst — consider a
  platform-appropriate share presentation on macOS
- Audit `removeParticipant` / other CloudKit share calls for the same
  main-thread blocking pattern fixed in Change 5 (likely cause of the
  "revoke invite" spin observed on iPhone) — done 2026-07-02 evening: all share
  operations now run off-main with a timeout
- Consolidate the two near-duplicate recipe pickers (`MealSlotComponents`
  "Add Meal" vs `MealSlotEditorSheet` "Select Recipe") — divergent wording and
  behavior caused a fix to land in the wrong one on 2026-07-02
- Plan/Log intuition gap: Plan is the shared household surface but is where
  users instinctively add personal meals; agreed direction is light-touch
  signage (mark Plan as household/shared, Log as private), not a flow fork
- ~~Planned-meal seeding invisible for unassigned meals~~ — RESOLVED 2026-07-03
  (99cf721): unassigned meals are household meals; they seed for every member
  with servings split across the household, assignment still narrows.
- Tiered macro estimation (product direction, user 2026-07-03): (1) recipe-backed
  meals derive macros from recipe ingredients — already works; (2) custom names
  resolve against local food/ingredient data — exists, pending parser
  unification; (3) NEW: when nothing local matches, estimate on-device with
  Apple's FoundationModels framework (iOS 26) — on-device only (nutrition is
  personal data; no cloud LLM), estimates keep the ≈ badge and stay editable,
  devices without Apple Intelligence fall back to the current static table.
  Subsumes the parser-unification item's end state.
- OPEN CRASH (2026-07-03, TestFlight 1.3 (78), iPhone 13 Pro): first use of
  Log → describe-a-meal ("mushroom omelette") crashed; NOT reproducible on the
  second attempt — first-run-only. Prime suspect: first-use warm-up of the
  Apple Intelligence LanguageModelSession in NaturalLanguageMealParser under a
  Release build (tests deliberately pin the regex path, so the AI path is
  untested in Release). Report was submitted via the system dialog and is no
  longer on-device — retrieve from Xcode Organizer → Crashes / ASC TestFlight
  feedback and symbolicate against the 2026-07-03 1.3 archive dSYM.
- ~~Manual sync refresh~~ — SHIPPED 2026-07-03: SyncRefreshButton (toolbar,
  next to settings on all layouts) calls PersistenceController.refreshFromCloud,
  a guarded store remove/re-add + viewContext reset (relaunch-equivalent
  catch-up import; no lighter public API exists per TN3164). Known limitation:
  the context reset can blink open UI holding object references — acceptable
  for a user-initiated action; revisit if it bites during the acceptance test.
- Share acceptance lands the participant on whatever tab was last open (Meal
  Log, observed 2026-07-03) instead of steering to the Plan tab like meal deep
  links do — add a Plan redirect in the userDidAcceptCloudKitShareWith path so
  a new member's first impression is the shared week, not their empty log.
- Xcode Thread Performance Checker flags `fetchShares` called synchronously on
  the main actor (hang risk, pre-existing). historyQueue QoS raised to
  userInitiated 2026-07-03; moving fetchShares off-main remains open.
