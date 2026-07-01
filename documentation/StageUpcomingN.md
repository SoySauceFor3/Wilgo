# Stage Upcoming = Closest N Commitments — Implementation Plan

**PRD:** [Stage view, future vs. catch up](https://www.notion.so/Stage-view-future-vs-catch-up-3884b58e32c380d1a4d8d7810c09962b)
**Tracking:** [Change upcoming criteria to be the closest N cmmt](https://www.notion.so/Change-upcoming-criteria-to-be-the-closest-N-cmmt-3884b58e32c3806d93f6d7375ba18af5)
**Tag:** #StageUpcomingN

---

## Context

Summary of the PRD decisions this plan implements:

- **Upcoming = the closest N commitments** whose nearest future _usable_ slot is soonest, sorted by that start time. Replaces the old `slotKind == .beforeNextToday` ("future of today") rule and its midnight cliff.
- **Per-commitment nearest-usable-slot; no horizon, no internal search bound.** For each commitment we compute its single _nearest usable slot start ≥ now_ (min over its finite slot set of each slot's next usable occurrence); we rank commitments by that value and take closest N. There is **no** `H`/search-window — a hidden bound could silently drop a valid slot and confusingly change what the user sees. N is the only cutoff. The search naturally crosses the cycle boundary because a slot's _next_ occurrence may fall in the next cycle (which is what kills the midnight cliff).
- **N counts commitments, not slots.** A commitment shows **one row** at its nearest usable slot and counts as 1 toward N. The row branches: **current-cycle** slot → time + "+k more" (k = current-cycle remaining usable − 1); **future-cycle** slot (any distance) → exact datetime + a "future cycle" marker, no "+k". (PRD §9 / Decision 4.)
- **N is a global user setting.** Default 3, **≥ 0** (0 hides Upcoming entirely), persisted in `AppSettings` (same pattern as `weekStartsOnMonday`). New Settings "Stage" section.
- **Cross-bucket priority rule:** a _behind_ commitment with a future usable slot qualifies for **both** Upcoming and Catch-up. **Upcoming wins if it makes the top-N**; otherwise it **demotes to Catch-up**. So the buckets are interdependent — Upcoming's N-cutoff changes Catch-up membership.
- **Empty Upcoming → the section is hidden.** (Already falls out of `StageView`'s `if !viewModel.upcoming.isEmpty`; no view change needed.)
- **Current and the goal-met /** `isActiveForReminders` **rule are unchanged.**

---

## Architecture Summary

Today, the three Stage lists are produced by three independent, mutually-exclusive
per-commitment classifiers (`currentWithBehind` / `upcomingWithBehind` /
`catchUpWithBehind`), each gating on a single `SlotStatusKind`. `StageViewModel.recompute()`
calls all three.

The new priority rule makes Upcoming and Catch-up **interdependent**: a behind commitment
with a future slot can satisfy both, and which bucket it lands in depends on a _global_
ranking + N-cutoff across all commitments. That can't be expressed by three independent
per-commitment filters.

**Solution:** introduce one coordinator, `CommitmentAndSlot.stageBuckets(commitments:now:n:) -> (current, upcoming, catchUp)`, that owns the three-way split and the priority rule as a
**pure function**. `recompute()` becomes a thin caller that reads `n` from settings and
assigns the result. The old per-commitment helpers are retained as private building blocks
the coordinator composes (Current is unchanged; Upcoming/Catch-up selection moves into the
coordinator).

This keeps all bucket logic in one unit-testable place (no `@MainActor`/`@Observable`
harness needed), and makes the Upcoming↔Catch-up dependency explicit and impossible to
desync.

### Bucket algorithm (the heart of the change)

Given `commitments`, `now`, and `n`:

1. **Active filter** (unchanged): drop commitments where `!isActiveForReminders(now:)`.
2. **Current**: active commitments with `slotKind == .insideSlot`. (Unchanged logic + sort.)
3. **Future-eligible**: active commitments **not** in Current that have a **nearest usable
   slot start ≥ now**. For each such commitment compute that nearest start as the **min over
   its slots** of each slot's **next occurrence start ≥ now** that is usable (snooze +
   saturation evaluated against that occurrence's **own cycle**). A commitment with no usable
   next occurrence on any slot has no nearest start → not future-eligible. Sort future-eligible
   commitments by that nearest start (then end).

- **No horizon / no scan.** Each slot contributes at most one candidate (its next
  occurrence) — a finite min over the commitment's slots, not a forward enumeration. See
  Decision 5.
- **Not cycle-bounded** `remainingSlots`**.** A slot's next occurrence can fall in the next
  cycle; `remainingSlots` stops at the current cycle end and would reintroduce the cliff.

1. **Upcoming** = `futureEligible.prefix(n)`.
2. **Overflow** = `futureEligible.dropFirst(n)` (future-eligible but beyond the cutoff).
3. **Catch-up** = all active commitments that are **behind** (`behindCount > 0`) AND
   **not in Upcoming**. This is the union of:

- the old catch-up set (behind, no future usable slot — formerly `.noSlotToday` + behind), and
- **overflow commitments that are behind** (the new demotion path).
  Sort by the existing catch-up urgency ordering.

So a behind commitment with a future slot: if it ranks in the top-N → Upcoming; else →
Catch-up. A non-behind commitment beyond the cutoff → appears in neither (it's fine; not
urgent, just not shown yet). This matches PRD §3 + §5.1.

---

## Design Decisions

### 1. Coordinator owns the buckets; N-cutoff lives there

**Decision:** add `CommitmentAndSlot.stageBuckets(commitments:now:n:)` as the single source
of bucket truth. `StageViewModel.recompute()` calls it.

**Why not compute the cutoff in** `recompute()`**?** The priority rule is the riskiest logic in
this feature and must be trivially unit-testable. In the VM it's only reachable through an
`@MainActor @Observable` harness; as a pure coordinator function it's tested directly. The
existing bucket tests are all commented out — we want the new logic testable without that
friction.

**Why not keep three independent helpers?** The new rule makes Upcoming and Catch-up
interdependent (Upcoming's cutoff changes Catch-up membership). Three independent filters
can't express that without duplicating the ranking in two places and risking desync.

**Risk:** behavior change to Catch-up (overflow demotion) could surface commitments that
previously didn't appear. **Mitigation:** explicit unit tests for the overflow→catch-up path
and the "non-behind overflow shows nowhere" path.

### 2. "Future usable slot" replaces `.beforeNextToday`

**Decision:** Upcoming eligibility = "has a nearest usable slot start ≥ now," instead of the
`slotKind == .beforeNextToday` calendar test.

**Why:** removes the midnight cliff (PRD §1). We stop using the per-commitment `slotKind`
calendar classification for Upcoming entirely.

**Note on** `SlotStatusKind`**:** `.beforeNextToday` is no longer used for bucket selection after
this change. We keep the enum case for now (still computed by `classifyKind`, still
potentially useful for diagnostics) but it no longer drives Upcoming. Removing it is out of
scope; flagged as possible later cleanup. _(See Open Items.)_

### 5. Per-commitment nearest-usable-slot — no horizon, no search bound

**Decision:** for each commitment, compute its **nearest usable slot start ≥ now** as the
`min` over its (finite) slot set of each slot's **next occurrence start ≥ now** that is usable.
Rank commitments by that value; take closest N. **No** `H`**, no time/occurrence search window.**

**Why no bound?** Slots are a fixed, finite set of `Slot` definitions, and we only need each
slot's _next_ occurrence — one known date per slot. So the per-commitment computation is a
finite `min` over slots, not a forward scan that needs a stop condition. There is simply
nothing to bound. A commitment whose every slot's next occurrence is unusable has _no_ nearest
start → not Upcoming-eligible (and if behind, Catch-up); that conclusion is reached without
scanning indefinitely.

**Why this matters (3Sauce's point):** a hidden time/occurrence horizon would be a cutoff the
user can't see, which could silently drop a valid upcoming slot and confusingly change the
list. With the per-commitment-min model, **N is the only cutoff** — the one rule the user
already understands. (Earlier draft proposed `H ≈ 3 days`; removed.)

**Why beyond the current cycle?** A slot's next occurrence ≥ now can land in the _next_ cycle
(11 PM → 7 AM-tomorrow on a daily cycle). This crossing is automatic from "next occurrence,"
not a separate scan — and it's what removes the midnight cliff. Restricting to the current
cycle (`status.remainingSlots`) would bring the cliff back.

**Risk — cross-cycle saturation (the part to get right):** when a slot's next occurrence is in
a future cycle, its saturation must be evaluated against **that occurrence's own cycle's**
check-ins, not the current cycle's. **Mitigation:** the helper resolves each occurrence's own
cycle window (via `cycle.bounds(including:)`) for its saturation check; Commit 3a tests this
with a multi-cycle setup.

### 3. N is a global UserDefaults setting, default 3, ≥ 0

**Decision:** new `AppSettings.upcomingCommitmentCountKey` + a computed accessor returning a
value clamped to **≥ 0** (default 3). **N = 0 is valid** — it means "show no Upcoming," and
falls out naturally (`prefix(0)` → empty → section hides). Settings UI uses a **TextField
(number pad) + Stepper hybrid** sharing one clamped `0...99` binding.

**Why not a Picker?** N has an open-ended range; the Picker pattern (Positivity Tokens 1–10)
assumes a small fixed set. **Why not a bare Stepper?** Tapping +/- to reach a large N (e.g. 20)
is tedious. **Why not a bare TextField?** Free text needs empty/non-numeric/out-of-range
handling. The **hybrid** gives direct number-pad entry _and_ nudge, with one clamped binding
centralizing validation — best of both, minimal validation surface.

**Risk:** unbounded N is meaningless past the user's commitment count. **Mitigation:** N only
caps the list; large N simply shows all future-eligible commitments. No correctness issue.

### 4. Upcoming row display — current-cycle "+k more" vs future-cycle marker

**Decision (PRD §9):** each Upcoming row shows the commitment's **nearest usable slot**, and
branches on whether that slot is in the **current** cycle or a **future** one:

- **Current cycle:** show the slot's time-of-day + **"+k more"** where
  **k = (current-cycle remaining usable slots) − 1**. Omit when k = 0. The count comes from the
  existing `status.remainingSlots.count`.
- **Future cycle (any distance, not just next):** show the slot's **exact datetime** + a clear
  **"future cycle"** marker. **Omit "+k more."** Do NOT label "next cycle" — it may be several
  cycles out. Exact datetime only (relative "in 3 days" is a later optimization).

**Why the branch:** when the nearest usable slot is past the current cycle (11 PM daily-cycle
→ 7 AM-tomorrow), the row must not present it as current-period progress. Distinct treatment
keeps it truthful at any distance.

**Engine support:** the per-commitment Upcoming entry carries
`(nearestSlot, nearestUsableInCurrentCycle: Bool, currentCycleRemainingCount: Int)` so the view branches
without re-deriving cycle math.

---

## Major Model Changes

| Entity                                                   | Change                                                                                                                                                                                                                                                                                                 |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Shared/AppSettings.swift`                               | **New** key `upcomingCommitmentCountKey` + computed `upcomingCommitmentCount` accessor (clamped ≥ 0, default 3; 0 = hide Upcoming).                                                                                                                                                                    |
| `Shared/Scheduling/Commitment+Status.swift`              | **New** helper returning the commitment's **nearest usable slot occurrence ≥ now** (`min` over its slots of each slot's next usable occurrence), with snooze + **per-cycle** saturation evaluated against each occurrence's own cycle. No horizon/scan.                                                |
| `Shared/Scheduling/CommitmentAndSlot.swift`              | **New** `stageBuckets(commitments:now:n:)` coordinator. `upcomingWithBehind` / `catchUpWithBehind` reworked into the coordinator's internals (Upcoming eligibility = has nearest usable slot; rank + `prefix(n)`; Catch-up = behind ∧ not-in-Upcoming, incl. overflow). `currentWithBehind` unchanged. |
| `Wilgo/Features/Stage/StageViewModel.swift`              | `recompute()` reads `n` from `AppSettings` and calls `stageBuckets`; assigns the three lists from one result. `upcoming` property retyped to `[UpcomingEntry]`.                                                                                                                                        |
| `Wilgo/Features/Stage/Upcoming.swift`                    | `UpcomingCommitmentRow` branches on `nearestUsableInCurrentCycle`: current → time + "+k more" (k = `currentCycleRemainingCount − 1`, omit if 0); future → exact datetime + "future cycle" marker, no count.                                                                                            |
| `Shared/Scheduling/CommitmentAndSlot.swift` (entry type) | The Upcoming entry extends the row inputs with `nearestUsableInCurrentCycle: Bool` and `currentCycleRemainingCount: Int` (a dedicated `UpcomingEntry` struct, or `WithBehind` + these fields). Current/Catch-up keep the existing `WithBehind`.                                                        |
| `Wilgo/Features/Settings/SettingsView.swift`             | **New** "Stage" section: number-pad TextField + Stepper hybrid over `@AppStorage` N (clamped `0...99`), with the PRD's label + footer copy.                                                                                                                                                            |

---

## Commit Plan

UI-affecting changes (Settings + row indicator) are sequenced early per CLAUDE.md so the
behavior can be manually verified against real data. Each commit builds, keeps tests green,
and ships its own unit tests with the source change.

### Phase 1 — Setting plumbing (no behavior change to Stage yet)

The goal is to introduce N as a persisted, user-visible setting before any logic depends on
it. Steps: add the AppSettings key/accessor, add the Settings UI.

#### Commit 1 — Add `upcomingCommitmentCount` to AppSettings

**Modify:** `Shared/AppSettings.swift`

```swift
/// How many commitments appear in the Stage's "Upcoming" list. Default: 3, minimum 0.
/// 0 is a valid choice — it hides the Upcoming section entirely.
static let upcomingCommitmentCountKey = "upcomingCommitmentCount"

/// Reads the Upcoming commitment count from UserDefaults. Returns 3 when absent;
/// clamps to a minimum of 0 (0 = user wants no Upcoming; negative would be meaningless).
static var upcomingCommitmentCount: Int {
    let raw = UserDefaults.standard.object(forKey: upcomingCommitmentCountKey) as? Int
    return max(0, raw ?? 3)
}
```

`n == 0` composes cleanly with the engine: `prefix(0)` → empty `upcoming` → the Stage view
already hides the empty section. No special-casing needed.

**Tests:** `WilgoTests/Settings/AppSettingsUpcomingCountTests.swift` — absent → 3; stored value
returned; **0 preserved (not clamped to 1)**; negative clamped to 0.

**Depends on:** none.

#### Commit 2 — Settings "Stage" section for N

**Modify:** `Wilgo/Features/Settings/SettingsView.swift` — add a `Section` mirroring the
existing Calendar/Positivity sections. Use a **TextField (number pad) + Stepper hybrid** on one
row, sharing a single clamped `Int` binding — type for a direct jump (e.g. N=20), tap +/- for
small nudges. The clamp keeps validation in one place; no free-text validation chaos.

- `@AppStorage(AppSettings.upcomingCommitmentCountKey) var upcomingCount = 3`
- A clamped binding (clamps to `0...99` on set) drives both controls, e.g.:

```swift
let countBinding = Binding(
    get: { min(max(upcomingCount, 0), 99) },
    set: { upcomingCount = min(max($0, 0), 99) }
)
Stepper {
    LabeledContent("Upcoming commitments shown") {
        TextField("", value: countBinding, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
    }
} onIncrement: { countBinding.wrappedValue += 1 }
  onDecrement: { countBinding.wrappedValue -= 1 }
```

(Exact layout is a UI detail; the requirement is: number-pad direct entry **and** stepper
nudge, both clamped to `0...99`, 0 allowed.)

- Header `Stage`; footer `How many commitments appear in the Stage's Upcoming list, ordered by which is due soonest. Default is 3.`

**Edge cases to handle:** empty field mid-edit (binding should not crash / should fall back to
last valid value — `.number` format + the clamp covers this); pasted non-numeric or out-of-range
input is clamped by the binding's `set`.

**Manual verification:** 🔵 build to a simulator/device, open Settings → confirm the Stage
section renders; typing a number persists; +/- nudges; entering 0 hides nothing yet but
persists 0; value survives relaunch. (No Stage behavior change yet — Stage still uses the old
helpers until Phase 2.)

**Depends on:** Commit 1.

### Phase 2 — Bucket coordinator (the behavior change)

The goal is to switch Upcoming to closest-N and wire the priority/demotion rule, behind a
pure, fully-tested coordinator. Steps: build the coordinator with tests, then point the VM at it.

#### Commit 3a — Nearest usable future slot (per-commitment)

**Modify:** `Shared/Scheduling/Commitment+Status.swift`

- Add a helper returning the commitment's **nearest usable slot occurrence with** `start ≥ now`:
  the `min` over its slots of each slot's next occurrence ≥ now, keeping only usable ones
  (snooze + saturation). **Saturation is evaluated against each occurrence's own cycle**
  (resolve via `cycle.bounds(including: occurrence.start)` — do **not** count against the
  current cycle when the occurrence is in a future cycle). Returns nil if no slot has a usable
  next occurrence. No horizon, no forward scan — one candidate per slot.

**Tests:** new `WilgoTests/Commitment/CommitmentNearestSlotTests.swift`:

- nearest future occurrence crossing midnight / cycle boundary is returned (no cliff).
- min across multiple slots returns the soonest.
- snoozed / saturated next occurrence excluded; falls through to a later usable slot or nil.
- **cross-cycle saturation**: a next occurrence in the _next_ cycle is saturated by _that_
  cycle's check-ins, and NOT mis-counted against the current cycle's. (Multi-cycle setup.)
- no usable next occurrence on any slot → nil.

**Depends on:** none (pure engine; parallel with Phase 1).

#### Commit 3b — `stageBuckets` coordinator + closest-N / demotion rule

**Modify:** `Shared/Scheduling/CommitmentAndSlot.swift`

- Define an `UpcomingEntry` (the row inputs + `nearestUsableInCurrentCycle: Bool` +
  `currentCycleRemainingCount: Int`). Current/Catch-up keep `WithBehind`.
- Add `static func stageBuckets(commitments:now:n:) -> (current: [WithBehind], upcoming: [UpcomingEntry], catchUp: [WithBehind])` implementing the algorithm in _Architecture Summary_, using the Commit 3a nearest-usable-slot helper for Upcoming eligibility + ranking.
- For each Upcoming entry, set `nearestUsableInCurrentCycle` = (nearest slot's start within
  `cycle.bounds(including: now)`) and `currentCycleRemainingCount` = `status.remainingSlots.count`.
- Rework Upcoming selection (nearest-usable-slot rank + `prefix(n)`) and Catch-up
  (behind ∧ not-in-Upcoming, including demoted overflow). `currentWithBehind` unchanged.
- Keep `nextTransitionDate` unchanged.

**Tests:** **un-comment and rewrite** `WilgoTests/Commitment/CommitmentAndSlot.swift` (currently
fully commented). New cases must cover:

- closest-N: > N future-eligible → exactly N in Upcoming, nearest first.
- < N future-eligible → all shown.
- 0 future-eligible → empty Upcoming.
- **overflow demotion**: a _behind_ commitment beyond the N cutoff appears in Catch-up.
- **non-behind overflow**: beyond cutoff and not behind → appears in neither.
- priority: a behind commitment within top-N appears in Upcoming, NOT Catch-up.
- multi-slot commitment counts as 1 toward N; `currentCycleRemainingCount` reflects its
  in-cycle usable slots.
- **midnight / cross-cycle**: a usable slot in a future cycle (e.g. 7AM-tomorrow seen at 11PM
  on a daily cycle) is eligible for Upcoming (no cliff) and its entry has
  `nearestUsableInCurrentCycle == false`.
- **current-cycle entry** has `nearestUsableInCurrentCycle == true` and the right remaining count.
- met-goal / `isActiveForReminders` exclusion still holds.

**Depends on:** Commit 3a.

#### Commit 4 — Point `StageViewModel` at the coordinator

**Modify:** `Wilgo/Features/Stage/StageViewModel.swift` — `recompute()` reads
`AppSettings.upcomingCommitmentCount`, calls `stageBuckets`, assigns `current/upcoming/catchUp`
from the one result. Remove the three separate helper calls. Change the `upcoming` property
type to `[CommitmentAndSlot.UpcomingEntry]` (Current/Catch-up stay `[WithBehind]`).

**Tests:** extend `WilgoTests/Stage/` — VM produces the demotion behavior end-to-end; changing
N changes the split.

**Manual verification:** 🔵 on device: with > N future commitments, confirm Upcoming shows N
and the rest (if behind) drop to Catch-up; change N in Settings and confirm Stage updates.

**Depends on:** Commit 1 (reads setting), Commit 3b (calls coordinator), Commit 2 (to exercise
the setting via UI — soft dependency for manual verification only).

### Phase 3 — Row polish

#### Commit 5 — Upcoming row: current-cycle "+k more" / future-cycle marker

**Modify:** `Wilgo/Features/Stage/Upcoming.swift` — `UpcomingCommitmentRow` branches on the
entry's `nearestUsableInCurrentCycle`:

- **Current cycle:** render the nearest slot's time-of-day; if
  `currentCycleRemainingCount - 1 > 0`, render a small "+k) more" secondary label.
- **Future cycle:** render the nearest slot's **exact datetime** (via `DateFormatter` /
  `Date.formatted` — no library needed) + a clear **"future cycle"** marker; no count.
  Update `#Preview`s to show: (a) current-cycle multi-slot ("+k more"), (b) future-cycle row.

The new fields (`nearestUsableInCurrentCycle`, `currentCycleRemainingCount`) are produced by the engine in
Commit 3b; this commit only consumes them in the view.

**Tests:** extract the small display-decision logic (which branch, what k) into a pure helper
and unit-test it: current-cycle k>0 → "+k more"; current-cycle k=0 → no label; future-cycle →
marker + dated string, no count. Visual layout verified via preview.

**Manual verification:** 🔵 preview / device: a current-cycle commitment with ≥2 usable slots
(shows "+k more"), and a commitment whose nearest usable slot is in a future cycle (shows exact
datetime + "future cycle" marker).

**Depends on:** Commit 3b (entry fields), Commit 4 (Upcoming populated).

---

## Open Items / Notes

- **N input range:** `0...99` — floor 0 (hide Upcoming), soft ceiling 99 for the stepper/field
  hybrid; revisit if a user genuinely needs more.

---

## Commit 6 — Characterization → Placement (single source of truth across all surfaces)

### Decisions log (3Sauce, this round)

1. **Restructure into two layers now** (not a simpler migration): characterization (`CommitmentSnapshot`)
   → placement (`stageBuckets(snapshots:n:)`). Supersedes the earlier "point everything at the existing
   `stageBuckets`" plan.
2. **CatchUpReminder reminds every behind commitment** (regardless of Stage bucket). Whether to also
   remind ones in an **open slot right now** is a **user setting, default OFF (exclude)** — open-slot
   commitments are already maximally visible, so a push is redundant; power users can opt in. Implemented
   as `behindForReminder(characteristics:includeCurrent:)` reading `AppSettings.includeActiveSlotsInCatchUp`.
   (See Commit 6e.)
3. **Snapshot carries ALL derived facts** (categorization + UI values), as **raw values not formatted
   strings**. It's the single "compute once" source; views read values and format at the boundary.
4. **Flat fields + computed accessors** (`isCurrent`/`isBehind`/`hasUpcoming`), MARK-grouped by concern.
   May convert to nested sub-structs later if it reads better.
5. **Explicit** `stageBuckets(snapshots:n:)` **+** `behindForReminder(snapshots:)` **API** — callers build
   snapshots once; no `commitments`-based wrapper. Keeps the layers honestly separate and lets a caller
   reuse one snapshot pass for both buckets and the reminder (the wrapper would re-hide snapshotting and
   force double computation for a both-buckets-and-reminder caller).
6. **Uniform characterization** over all _active_ commitments — compute `nearestUsable` even for
   current-slot ones (clean one-path over a micro-optimization; negligible at Stage-sized N).
7. **Sorting stays in the engine** (per-bucket), never the UI — ordering is domain logic, identical
   across surfaces.
8. **Finer commits — one consumer surface per commit.**
9. **Recompute sweep (uncommitted) is subsumed** into 6b's snapshot pass; not committed separately.
10. `CommitmentCharacteristics` (renamed from `CommitmentSnapshot` — name clash with the widget's
    existing `CommitmentSnapshot` display DTO; new name also matches the "characterization" framing).
    Stores `currentOccurrence` + `remainingThisCycleCount` (a count, not the slot array — no consumer
    needs the full list).
11. `remainingThisCycleCount` **INCLUDES the currently-open slot(s).**

- _Why not exclude?_ The Current row's old label "Next Up: N" did `count - 1` to drop the slot it
  shows. But **multiple slots can be open at once** (two windows both contain `now`) — then "the
  current one" is plural and `- 1` is wrong (it'd hide a second open slot). A single "remaining
  minus current" field is ill-defined in that case, and "exclude which one?" also differs by surface
  (Current excludes the open slot; Upcoming excludes the nearest).
  - _Decision:_ the field is the raw fact "usable slots remaining in the cycle, including any open
    ones." Presentation does **not** subtract. The label changes to **"N slots remaining"** (plural-safe,
    correct for 0/1/many open slots), shown under the headline slot time. This keeps the engine a pure
    fact-emitter and fixes the latent multi-current bug. Label work lands in **6c** (Stage rows).

1. **`characteristics` becomes the single computation; `status()`/`CommitmentStatus`/`slotStatus`/
   `SlotStatus`/`SlotStatusKind`/`classifyKind` are deleted.** 6a wraps `status()` for now, but the END
   commit (6g) inlines the slot+goal computation into `characteristics` and removes the intermediate
   types. Sequenced last because the old `*WithBehind` helpers still call `status()`/`slotStatus()`
   until the surfaces migrate (6d–6f) — inlining earlier would break the build or duplicate logic.
   Lower-level pieces `characteristics` still uses are kept (`goalProgress`, `remainingUsableOccurrences`,
   `nearestUsableUpcomingOccurrence`, `isActiveForReminders`).

### Bug + design smell this fixes

After Commit 4 the **Stage** uses `stageBuckets` (closest-N + overflow demotion + respects `n`),
but the **widget** and **CatchUpReminder** still call the OLD per-kind helpers, so surfaces **disagree**:

- Widget "Upcoming" = old `.beforeNextToday` rule (today-only, midnight cliff), ignores `n`.
- Widget "Catch-up" = old `.noSlotToday` only → misses overflow demotion.
- CatchUpReminder uses the same stale rule.

Deeper: `stageBuckets` **tangles two responsibilities** — _characterizing_ a commitment (its facts)
and _placing_ it into a row. CatchUpReminder doesn't want rows; it wants "everyone behind" — including
commitments that the bucketing would hide inside Upcoming's top-N. Reading the _bucket_ layer can't
express that; reading a _characterization_ layer can.

### Design: two layers

1. **Characterization —** `CommitmentSnapshot` (one commitment → ALL its facts at `now`, no
   cross-commitment knowledge). Carries every derived value a consumer needs — categorization fields
   **and** UI values — as raw values, never formatted strings (formatting stays at the view boundary).
   Flat stored fields + computed accessors for readability (`isCurrent`, `isBehind`, `hasUpcoming`),
   organized by concern with `// MARK:` (may convert to nested sub-structs later if it reads better):

- Computed **uniformly** for every _active_ commitment (incl. current-slot ones — `nearestUsable`
  is computed for all; cost is negligible at Stage-sized N). `isActiveForReminders` is applied once
  at the boundary so both consumers inherit the goal-met rule.
- Field set finalized against what the row views actually read: Current/CatchUp rows use
  `remainingThisCycle` (first slot + count) + `behindCount`; `CommitmentStatsCard` uses
  `checkInCount`/`targetCount`; Upcoming uses `nearestUsable`/`nearestUsableInCurrentCycle`/
  `remainingThisCycle.count`.

1. **Placement —** `stageBuckets(snapshots:n:)` (across snapshots → rows): Current = `isCurrent`;
   Upcoming = non-current with `nearestUsable`, ranked by start, `prefix(n)`; Catch-up = behind and
   not in Current/Upcoming (overflow demotion). Per-bucket **sorting lives here** (current by remaining
   fraction, upcoming by nearest start, catch-up by urgency) — ordering is domain logic, identical
   across surfaces, so never in the UI.

### Consumers

- **Stage** → `stageBuckets(snapshots:n:)` (rows).
- **Widget** → same buckets (now respects `n` + closest-N + demotion). Upcoming stays simple
  (nearest slot time only, no "+k more"/future chrome — limited widget space; sync is about _which_
  commitments show, not chrome).
- **LiveActivity** → `stageBuckets(...).current`.
- **CatchUpReminder** → `behindForReminder(snapshots:) = snapshots.filter { $0.behindCount > 0 && !$0.isCurrent }`.
  Reads the **characterization** layer, so it reminds every behind commitment regardless of which row
  it would render in — **except** ones in an open slot now (they're being acted on; a nudge would be
  redundant). This is the semantic fix.

### Then delete orphaned machinery

`currentWithBehind` / `upcomingWithBehind` / `catchUpWithBehind`, `SlotStatusKind`, `classifyKind`,
the `slotKind` field on `CommitmentStatus`, and the `.disabled` path in `status()` — all unused once
the surfaces move onto snapshots/buckets.

### Architectural principles applied (answers to recurring design Qs)

- **Compute decisions+values in the engine; format strings at the view boundary.** The engine emits a
  `SlotOccurrence` / an `Int` k / a `UpcomingRowDisplay` _decision_, not a pre-rendered localized string.
  A pure `datedLabel` on the model is fine (testable), but core logic must not return display strings —
  that couples it to presentation and kills reuse.
- **Sorting is domain logic → in** `CommitmentAndSlot`**, never the UI.** Same order everywhere; the view
  renders the array as given.
- **Characterize once, place many.** One commitment → one fact bundle; placement/filtering are pure
  functions over the bundles.

### Tests

- `CommitmentSnapshot`: per-commitment facts (isCurrent, behindCount, nearestUsable, nearestUsableInCurrentCycle).
- `stageBuckets(snapshots:n:)`: existing 11 bucket cases, rebuilt over snapshots.
- `behindForReminder`: includes a behind commitment that's in Upcoming's top-N; excludes a behind
  current-slot one.
- Widget + CatchUpReminder produce buckets/reminders consistent with the engine.
- Full suite green after deletions.

### Commit plan (each commit builds + tests green)

**API:** explicit `stageBuckets(snapshots:n:)` and `behindForReminder(snapshots:)` — callers build
snapshots once, then place and/or filter. No `commitments`-based wrapper (keeps the two layers honestly
separate; lets a caller reuse one snapshot pass for both buckets and the reminder).

> Note: the uncommitted "recompute sweep" in the working tree is **subsumed** here — its `statusByID`
> idea becomes the snapshot pass. It is not committed separately. (If the tree still holds it when 6a
> starts, fold it in rather than committing it on its own.)

- **6a —** `CommitmentCharacteristics` **+** `characteristics(of:now:)`**.** The characterization layer (pure
  addition; no consumers yet, old code untouched). Computed uniformly for active commitments. Tests:
  per-commitment facts. _Builds green: nothing depends on it._ _(Done.)_
  - Named `CommitmentCharacteristics` (not `CommitmentSnapshot` — the widget already has a
    `CommitmentSnapshot` display DTO; this name also matches the "characterization" framing).
  - Stores `currentOccurrence` + `remainingThisCycleCount` (a count, not the `[SlotOccurrence]`
    array — no consumer needs the full list). The count **includes** the currently-open slot(s); it's
    a raw "how many remain" fact (multiple slots can be open at once, so a "minus the current one"
    field would be ambiguous). Row labels do not subtract — see 6c.
- **6b —** `stageBuckets(snapshots:n:)` **+** `behindForReminder(snapshots:)`**, and migrate the Stage VM.**
  Re-implement bucketing over snapshots (per-bucket sorting stays here); add the reminder filter. The
  old `stageBuckets(commitments:now:n:)` signature is replaced, so `StageViewModel.recompute` **is
  updated in this same commit** to build snapshots then call the new API (otherwise it wouldn't build).
  Old `*WithBehind` helpers remain (still used by widget/notifications). Tests: rebuilt 11 bucket cases
  - `behindForReminder` cases. _Builds green: only the VM caller changes alongside the signature._
  - **Open decision (settle in 6b): the Current/Catch-up bucket element type.** Today they're
    `[WithBehind]`. `WithBehind` is deleted in 6g, so they need a replacement — either
    `[CommitmentCharacteristics]` directly (rows read facts off it) or small per-bucket entry structs.
    `UpcomingEntry` **stays** (it carries row-display extras + `rowDisplay`), just rebuilt from a
    `CommitmentCharacteristics`. Decide when the row needs are concrete during 6b.
- **6c — Stage rows: wire to characteristics + "N slots remaining" label.**
  Now that the Stage VM exposes characteristics-derived data (6b), update the Stage row views to read it
  and fix the slot-count label:
  - **Current row** (`Current.swift`): replace `"Next Up: \(slots.count - 1) slots"` with
    `"\(remainingThisCycleCount) slots remaining"` (plural-safe). The count includes any open
    slot(s) — no `- 1` — which fixes the latent bug where 2 simultaneously-open slots showed a wrong
    "Next Up" number. The headline slot time still comes from `currentOccurrence`.
  - **CatchUp row** (`CatchUp.swift`): same "N slots remaining" wording for consistency (it already
    shows a raw count; just align the label).
  - **Upcoming row**: already shows the nearest slot + "+k more" (Commit 5); unchanged here.
  - Drop the dead `slotOccurences:` parameter from `CommitmentStatsCard` if convenient (it's unused).
  - **Tests:** the label/count decision logic is pure — extract + unit test (`remainingThisCycleCount`
    → "N slots remaining"; multi-open-slot case shows the full count, not count-1). Visual via preview.
  - _Builds green._
- **6d — Migrate widget** (`CurrentCommitmentWidget.buildSnapshots`) to characteristics → `stageBuckets`.
  Widget Upcoming stays simple (nearest slot time only). Test: widget buckets match the engine
  (respects `n`, closest-N, demotion). _Builds green._
- **6e — Migrate CatchUpReminder to** `behindForReminder`**, made user-configurable.**
  CatchUpReminder reminds **every behind commitment** (not just the Stage's catch-up bucket — a behind
  commitment sitting in Upcoming's top-N still needs catching up). It builds `characteristics` for all
  reminders-enabled, active commitments and filters via `behindForReminder`.
  - **New decision — "include active slots" is a user setting.** Whether to also remind a behind
    commitment whose slot is **open right now** is now a user choice, **default OFF (exclude)**:
    - _Why default exclude:_ an open-slot commitment is already maximally visible (Stage row + Live
      Activity) and the user is in the window to act, so a push notification is redundant/nagging.
      Excluding loses little; including risks annoyance. (Power users who want "remind whenever behind"
      can turn it on.)
  - **Setting:** `AppSettings.includeActiveSlotsInCatchUpReminder` (UserDefaults, default `false`). Settings UI:
    a **"Notifications" → "Catch-up reminders"** area with a toggle **"Include active slots"**.
  - **Engine:** `behindForReminder(characteristics:includeCurrent:)` — `filter { isBehind && (includeCurrent || !isCurrent) }`,
    `includeCurrent` defaulting `false`. The engine stays a pure rule; CatchUpReminder reads the setting
    and passes the bool (setting access stays at the call-site boundary, not in the engine).
  - **Tests:** `behindForReminder` both branches (include vs exclude current); a behind-in-Upcoming case
    is still reminded; the AppSettings flag default/read.
  - _Builds green._
- **6f — Migrate LiveActivityRefresher** to `stageBuckets(snapshots:n:).current`. _Builds green._
- **6g — Inline everything into** `characteristics`**; delete the intermediate engine.** After 6b–6f no
  surface uses the old `*WithBehind` helpers or `status()`/`CommitmentStatus` (only `characteristics`
  does). So:
  - **Inline** the slot + goal computation directly into `characteristics(of:now:)`: compute remaining
    usable occurrences + `goalProgress` inline and derive `behindCount` there. `characteristics` becomes
    the single function that computes everything from a commitment + `now`.
  - **Delete** `currentWithBehind`/`upcomingWithBehind`/`catchUpWithBehind`; the `WithBehind` typealias
    (its last users are those helpers); `status()` +
    `CommitmentStatus`; `slotStatus()` + `SlotStatus`; `SlotStatusKind`; `classifyKind`; the `.disabled`
    path. (Keep the lower-level pieces `characteristics` still needs: `goalProgress`,
    `remainingUsableOccurrences`/`slotOccurrences`, `nearestUsableUpcomingOccurrence`,
    `isActiveForReminders`.)
  - **Rewrite** `StatusTests.swift` — it tests `status()`/`slotKind` directly; re-target the still-meaningful
    assertions at `characteristics` (much is already covered by `CommitmentCharacteristicsTests`; delete
    redundant cases, keep unique ones).
  - _Builds green: every other caller is gone by now; this commit removes the types and their last user
    (the wrapper) in one step — no duplication at any point._

Ordering rule: add the new layer (6a–6b) → migrate/adjust consumers one surface per commit (6c–6f) →
inline + delete the intermediate engine only once nothing else references it (6g). Rationale for doing
the inline at the END (not in 6a): `status()`/`slotStatus()` are still called by the old `*WithBehind`
helpers until 6d–6f migrate the widget/CatchUpReminder/LiveActivity off them — inlining earlier would
either break the build or force duplicated logic across several commits. 6c/6d/6e/6f are independent.

Open issues:

1. [ ] should we keep the bucket func? not every place need to calculate all current, future and catchup.
2. [x] func `slotOccurrences` should change to be day-time boundaries and allow deciding if the one starts in the boundary but does not end on boundary should be counted.
