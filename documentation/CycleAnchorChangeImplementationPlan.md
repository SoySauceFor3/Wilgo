# Cycle Anchor Change: Implementation Plan

> PRD: `documentation/Cycle Anchor Change.md`
> Goal: weekly cycles always start Monday, monthly cycles always start on the 1st. Trial — must be backward-compatible.

---

## Key Data Structure Changes

### 1. New: `GracePeriod` (new file `Shared/Models/GracePeriod.swift`)

Designed broadly to support future use cases (vacation/disable) beyond creation and rule-change.

```swift
struct GracePeriod: Codable, Hashable {
    var startPsychDay: Date   // inclusive — first day of grace
    var endPsychDay: Date     // exclusive — first day past grace
    var reason: GraceReason

    /// True if this grace period overlaps with the given cycle window.
    func overlaps(cycleStart: Date, cycleEnd: Date) -> Bool {
        startPsychDay < cycleEnd && endPsychDay > cycleStart
    }
}

enum GraceReason: String, Codable {
    case creation    // commitment created mid-cycle, user opted in
    case ruleChange  // target changed, user chose grace period
    case disabled    // commitment temporarily disabled (future: vacation)
}
```

Why date ranges (not a single date or per-cycle flags): the `overlaps()` logic handles all cases uniformly — single cycles (creation/rule-change: `startPsychDay = cycleStart, endPsychDay = cycleEnd`) and multi-cycle ranges (vacation: `startPsychDay = disableDate, endPsychDay = enableDate`).

### 2. Changed: `Commitment` — add `gracePeriods`

```swift
// New field on Commitment (default = [] for backward compatibility)
var gracePeriods: [GracePeriod] = []
```

No other field needed. No `scheduledTarget` or `scheduledEffectiveDate` — the target always changes immediately (per PRD principle 1), and grace is tracked separately.

SwiftData handles the new optional array via lightweight migration — no explicit migration plan needed, but schema should be versioned in `WilgoApp.swift`.

### 3. New: `Cycle.makeDefault(kind:on:)` — the intercepting function

A single new static function added to `Cycle.swift`. **No changes to any existing `Cycle` functions.**

```swift
/// Creates a Cycle anchored to the canonical start day for the given kind:
///   daily   → today's psych-day (unchanged behavior)
///   weekly  → most recent Monday on or before `date`
///   monthly → 1st of the month containing `date`
static func makeDefault(_ kind: CycleKind, on date: Date = Time.now()) -> Cycle
```

### 4. Changed: `CycleReport` — add `isGrace`

```swift
// In FinishedCycleReport/Models.swift
let isGrace: Bool   // true → no penalty, no PT tokens applied
```

---

## Alternatives Considered

### A. GracePeriod storage


| Option                                                | Pros                                                                                     | Cons                                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `[GracePeriod]` array on Commitment **(chosen)**      | Supports multiple grace periods; vacation use case fits naturally via date-range overlap | Slightly more complex than a single date                                  |
| Single `scheduledEffectiveDate: Date?`                | Simpler, matches PRD's original field name                                               | Only one grace window; doesn't support vacation without redesign          |
| Separate `@Model class GracePeriod` with relationship | Full SwiftData querying capability                                                       | Overkill for simple date ranges; adds join overhead; complicates deletion |


### B. Cycle anchor interceptor pattern


| Option                                                 | Pros                                                                                                   | Cons                                                                           |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| New `Cycle.makeDefault()` static function **(chosen)** | Purely additive; `Cycle.anchored()` and all preview/test call sites unchanged; revert = 3 line changes | Requires callers to opt in                                                     |
| Modify `Cycle.anchored()`                              | One change affects all callers                                                                         | Breaks backward compatibility; existing previews and tests would need updating |
| New `CycleFactory.swift` file                          | Cleaner separation                                                                                     | Extra indirection for a simple helper                                          |


### C. SwiftData migration approach


| Option                                         | Pros                                                                                    | Cons                                                        |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Lightweight migration (automatic) **(chosen)** | No boilerplate; SwiftData handles adding Codable properties with defaults automatically | Less explicit; no migration test without extra setup        |
| Versioned `SchemaMigrationPlan`                | Explicit; testable; auditable                                                           | Required only when removing/renaming fields — overkill here |


SwiftData stores `[GracePeriod]` (a `Codable` struct array, not a `@Model`) as a serialized attribute column. Adding it with `= []` default is a lightweight-compatible change. We verify correctness with a migration test in Commit 2.

### D. Grace modal UI pattern


| Option                                     | Pros                                                                                | Cons                                                         |
| ------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| SwiftUI `.confirmationDialog` **(chosen)** | Native iOS feel; lightweight; appears from bottom like iOS sleep schedule reference | Limited custom layout                                        |
| Custom `.sheet`                            | Full layout control                                                                 | Heavier, more code for a two-choice question                 |
| `.alert`                                   | Simplest                                                                            | Top-of-screen, doesn't match iOS sleep schedule UX reference |


### E. Grace detection in report


| Option                                                    | Pros                                                                  | Cons                                                                        |
| --------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `gracePeriods.contains { $0.overlaps(...) }` **(chosen)** | General; works for all GraceReason variants including future vacation | Iterates array per cycle (negligible for small arrays)                      |
| Store grace cycle start dates as `Set<Date>`              | O(1) lookup                                                           | Only works for exact cycle boundaries; breaks for vacation ranges mid-cycle |


---

## Step-by-Step Commits

### Commit 1 — `GracePeriod` model (pure logic, no DB change)

**Files:** `Shared/Models/GracePeriod.swift` (new)

- Create `GracePeriod.swift` with struct + `GraceReason` enum
- No changes to `Commitment` or SwiftData schema yet
- No behavior change anywhere — isolated type definition

---

### Commit 2 — SwiftData schema migration: add `gracePeriods` to `Commitment`

**Files:** `Shared/Models/Commitment.swift`, `WilgoApp.swift`

- Add `var gracePeriods: [GracePeriod] = []` to `Commitment`
- Bump `Schema` version comment in `WilgoApp.swift` (document the change even if no explicit migration plan is needed)
- **Migration verification:** write a unit test that:
  1. Creates an in-memory `ModelContainer` without `gracePeriods`
  2. Inserts a `Commitment` and saves
  3. Re-opens the store with the new schema
  4. Verifies `gracePeriods` is `[]` on the loaded record
- No behavior change — field is inert, defaulting to `[]`

*Why a separate commit from Commit 1:* the schema change and its verification are a distinct, reviewable step from the type definition.

---

### Commit 3 — `Cycle.makeDefault` canonical anchor factory

**Files:** `Shared/Models/Cycle.swift`

- Add `static func makeDefault(_ kind: CycleKind, on date: Date = Time.now()) -> Cycle`
- Add two private helpers:
  - `mostRecentMonday(on date: Date)` — `(weekday - 2 + 7) % 7` days back (1=Sun, 2=Mon)
  - `firstOfMonth(for date: Date)` — year+month comps, day=1
- Zero changes to existing functions
- Unit tests:
  - `makeDefault(.weekly)` on Monday → same day
  - `makeDefault(.weekly)` on Wednesday → prior Monday
  - `makeDefault(.monthly)` on 15th → 1st of that month
  - `makeDefault(.monthly)` on 1st → same day
  - `makeDefault(.daily)` → today

---

### Commit 3.5 — Canonical anchor in creation path

**Files:** `Features/Commitments/AddCommitView.swift`, `Features/Commitments/CommitmentFormFields.swift`

`**CommitmentFormFields.swift` — `targetCycleKindBinding.set`:

```swift
// Before:
target.cycle = Cycle.anchored(newKind, at: .now)
// After:
target.cycle = Cycle.makeDefault(newKind)
```

---

### Commit 4 - Creation modal

**Files:** `AddCommitView.swift`:

1. Initial default: `Cycle.makeDefault(.daily)` instead of `Cycle.anchored(.daily, at: .now)`
2. `saveCommitment()` trigger `.confirmationDialog`:

> "[This week/month]/[Today] has already started (if week/month show start date of week/month). Should it count toward penalties?"  
> **[Yes — I'm committed]** → save, no grace period
> **[No — grace period]** → save, then append `GracePeriod(start: cycleStart, end: cycleEnd, reason: .creation)` to the new commitment

---

### Commit 5 — Edit flow: rule-change modal + grace period recording

**Files:** `Features/Commitments/EditCommitmentView.swift`

1. Remove `rulesChangedNote` from `CommitmentFormFields` call (replaced by the modal)
2. In `saveChanges()`: when `anyRuleChanged`, trigger `.confirmationDialog` instead of saving directly:
  > "Your goal changes to [X per cycle] now. Should this [week/month/today] count toward penalties?"  
  > **[Yes — I'm committed now]** → `saveChanges(grace: false)`
  > **[No — grace period]** → `saveChanges(grace: true)`
3. In `saveChanges(grace:)`:

- Use `Cycle.makeDefault(target.cycle.kind)` instead of `Cycle.anchored(target.cycle.kind, at: Time.now())`
- If `grace == true`: append `GracePeriod(start: cycleStart, end: cycleEnd, reason: .ruleChange)` to `commitment.gracePeriods`
- Same-kind edits: boundaries unchanged (re-anchor is no-op for same kind with canonical anchor)
- CycleKind change: new canonical anchor applies; grace (if chosen) covers the transition cycle

No modal when `!anyRuleChanged` — direct save as before.

---

### Commit 6 — FinishedCycleReport: `isGrace` in models + builder

**Files:** `FinishedCycleReport/Models.swift`, `FinishedCycleReport/PreTokenReportBuilder.swift`

`**Models.swift`: add `let isGrace: Bool` to `CycleReport` (default `false` at all existing init sites).

`**PreTokenReportBuilder.swift` — in `cyclesForCommitment`, after computing `cycleStart`/`cycleEnd`:

```swift
let isGrace = commitment.gracePeriods.contains {
    $0.overlaps(cycleStart: cycleStart, cycleEnd: cycleEnd)
}
```

Propagate through `CycleDraft` → `CycleReport` init.

Grace cycles still appear in the report — no changes to `nextCompletedCycleEnd` or iteration logic.

---

### Commit 7 — FinishedCycleReport: PT compensator + UI verdict

**Files:** `FinishedCycleReport/PositivityTokenCompensator.swift`, `FinishedCycleReport/CheckInSummaryPage.swift`

`**PositivityTokenCompensator.swift`: skip any cycle where `isGrace == true` — no PT consumed, monthly cap unaffected.

`**CheckInSummaryPage.swift`: for grace cycles, show "no penalty · grace period" instead of the normal `metTarget` verdict. Visual style: neutral/secondary (not a failure indicator).

---

### Commit 8 — Tests

**Files:** `WilgoTests/`

- `GracePeriodTests.swift` (new): `overlaps()` single-cycle, multi-cycle, exact boundary dates
- `CycleDefaultAnchorTests.swift` (new): `makeDefault` across all kinds and representative dates
- `FinishedCycleReportBuilderTests.swift` (existing): grace cycle cases — verify grace cycles appear in report but `isGrace == true` and no PT applied

---

## Files Changed Per Commit


| Commit | Files                                                                                                  |
| ------ | ------------------------------------------------------------------------------------------------------ |
| 1      | `Shared/Models/GracePeriod.swift` (new)                                                                |
| 2      | `Shared/Models/Commitment.swift`, `WilgoApp.swift`                                                     |
| 3      | `Shared/Models/Cycle.swift`                                                                            |
| 4      | `Features/Commitments/AddCommitView.swift`, `Features/Commitments/CommitmentFormFields.swift`          |
| 5      | `Features/Commitments/EditCommitmentView.swift`                                                        |
| 6      | `FinishedCycleReport/Models.swift`, `FinishedCycleReport/PreTokenReportBuilder.swift`                  |
| 7      | `FinishedCycleReport/PositivityTokenCompensator.swift`, `FinishedCycleReport/CheckInSummaryPage.swift` |
| 8      | `WilgoTests/` (new + existing test files)                                                              |


---

## Backward Compatibility

- All existing `Commitment` records keep their `referencePsychDay` — old Wed–Tue weeklies continue unchanged
- `gracePeriods` defaults to `[]` — zero effect on existing commitments
- `Cycle.anchored()` is untouched — all existing preview/test call sites compile unchanged
- **Revert path:** swap 3 `Cycle.makeDefault` calls back to `Cycle.anchored(kind, at: .now)` in AddCommitView, CommitmentFormFields, EditCommitmentView. Drop GracePeriod field (requires schema migration back).

---

## Verification (matches PRD)

1. New weekly commitment on Wednesday → Stage shows Mon–Sun; first report shows grace verdict if chosen
2. New monthly commitment on 15th → cycle is 1st–31st; grace offered at creation
3. Edit count, "committed now" → new count everywhere, current cycle penalized
4. Edit count, "grace period" → new count everywhere, current cycle shows "no penalty · grace period"
5. Edit weekly→monthly, grace → Stage shows monthly goal immediately; transition cycle is grace
6. Edit with no rule change → no modal, direct save
7. Existing commitment → unchanged boundaries, `gracePeriods` empty, no effect

