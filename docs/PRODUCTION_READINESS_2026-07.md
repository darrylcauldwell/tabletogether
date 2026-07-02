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
| 2 | Undeployed CloudKit schema (`Recipe.sourceUID`) | Manual: deploy Dev→Production in CloudKit Dashboard, then `scripts/mark-schema-deployed.sh` |
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

Design (detailed before implementation; research first):
- Each device generates and persists a unique "Me" UUID; stop seeding the
  well-known constant for new users.
- Migrate existing devices: relabel the locally-created legacy "Me" row (the one in
  the private store) to the device UUID; leave mirrored rows alone.
- `User.current(in:)` resolves by the device UUID only.
- Meal-slot assignment matching keys on the resolved user object, never a shared
  constant.

**Acceptance:** two-device shared household — assignments on device A never appear
in device B's private log; existing single-device data survives upgrade.

## Change 4 — Documentation fix

`APP_STORE_CONNECT_SETUP.md` lists the tvOS bundle ID as
`dev.dreamfold.tabletogethertv`; actual is `dev.dreamfold.tabletogether.tv`.

## Deferred (tracked, not in this spec)

- Tests for dedup / store reset / sharing purge / PrivateDataManager offline paths
- Versioned Core Data model + migration test before next schema change
- `Household+Transferable` fatalError on malformed payload
- In-app prompt for orphaned private-zone recovery (beyond Change 2 banner)
