# Stage Upcoming = Closest N Commitments — Implementation Plan

**PRD:** [Stage view, future vs. catch up](https://www.notion.so/Stage-view-future-vs-catch-up-3884b58e32c380d1a4d8d7810c09962b)
**Tracking:** [Change upcoming criteria to be the closest N cmmt](https://www.notion.so/Change-upcoming-criteria-to-be-the-closest-N-cmmt-3884b58e32c3806d93f6d7375ba18af5)
**Tag:** #StageUpcomingN

---

## Context

Summary of the PRD decisions this plan implements:

- **Upcoming = the closest N commitments** whose nearest future *usable* slot is soonest, sorted by that start time. Replaces the old `slotKind == .beforeNextToday` ("future of today") rule and its midnight cliff.
- **Per-commitment nearest-usable-slot; no horizon, no internal search bound.** For each commitment we compute its single *nearest usable slot start ≥ now* (min over its finite slot set of each slot's next usable occurrence); we rank commitments by that value and take closest N. There is **no** `H`/search-window — a hidden bound could silently drop a valid slot and confusingly change what the user sees. N is the only cutoff. The search naturally crosses the cycle boundary because a slot's *next* occurrence may fall in the next cycle (which is what kills the midnight cliff).
- **N counts commitments, not slots.** A commitment shows **one row** at its nearest usable slot and counts as 1 toward N. The row branches: **current-cycle** slot → time + "+k more" (k = current-cycle remaining usable − 1); **future-cycle** slot (any distance) → exact datetime + a "future cycle" marker, no "+k". (PRD §9 / Decision 4.)
- **N is a global user setting.** Default 3, **≥ 0** (0 hides Upcoming entirely), persisted in `AppSettings` (same pattern as `weekStartsOnMonday`). New Settings "Stage" section.
- **Cross-bucket priority rule:** a *behind* commitment with a future usable slot qualifies for **both** Upcoming and Catch-up. **Upcoming wins if it makes the top-N**; otherwise it **demotes to Catch-up**. So the buckets are interdependent — Upcoming's N-cutoff changes Catch-up membership.
- **Empty Upcoming → the section is hidden.** (Already falls out of `StageView`'s `if !viewModel.upcoming.isEmpty`; no view change needed.)
- **Current and the goal-met / `isActiveForReminders` rule are unchanged.**

---

## Architecture Summary

Today, the three Stage lists are produced by three independent, mutually-exclusive
per-commitment classifiers (`currentWithBehind` / `upcomingWithBehind` /
`catchUpWithBehind`), each gating on a single `SlotStatusKind`. `StageViewModel.recompute()`
calls all three.

The new priority rule makes Upcoming and Catch-up **interdependent**: a behind commitment
with a future slot can satisfy both, and which bucket it lands in depends on a *global*
ranking + N-cutoff across all commitments. That can't be expressed by three independent
per-commitment filters.

**Solution:** introduce one coordinator, `CommitmentAndSlot.stageBuckets(commitments:now:n:)
-> (current, upcoming, catchUp)`, that owns the three-way split and the priority rule as a
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
   - **Not cycle-bounded `remainingSlots`.** A slot's next occurrence can fall in the next
     cycle; `remainingSlots` stops at the current cycle end and would reintroduce the cliff.
4. **Upcoming** = `futureEligible.prefix(n)`.
5. **Overflow** = `futureEligible.dropFirst(n)` (future-eligible but beyond the cutoff).
6. **Catch-up** = all active commitments that are **behind** (`behindCount > 0`) AND
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

**Why not compute the cutoff in `recompute()`?** The priority rule is the riskiest logic in
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

**Note on `SlotStatusKind`:** `.beforeNextToday` is no longer used for bucket selection after
this change. We keep the enum case for now (still computed by `classifyKind`, still
potentially useful for diagnostics) but it no longer drives Upcoming. Removing it is out of
scope; flagged as possible later cleanup. *(See Open Items.)*

### 5. Per-commitment nearest-usable-slot — no horizon, no search bound

**Decision:** for each commitment, compute its **nearest usable slot start ≥ now** as the
`min` over its (finite) slot set of each slot's **next occurrence start ≥ now** that is usable.
Rank commitments by that value; take closest N. **No `H`, no time/occurrence search window.**

**Why no bound?** Slots are a fixed, finite set of `Slot` definitions, and we only need each
slot's *next* occurrence — one known date per slot. So the per-commitment computation is a
finite `min` over slots, not a forward scan that needs a stop condition. There is simply
nothing to bound. A commitment whose every slot's next occurrence is unusable has *no* nearest
start → not Upcoming-eligible (and if behind, Catch-up); that conclusion is reached without
scanning indefinitely.

**Why this matters (3Sauce's point):** a hidden time/occurrence horizon would be a cutoff the
user can't see, which could silently drop a valid upcoming slot and confusingly change the
list. With the per-commitment-min model, **N is the only cutoff** — the one rule the user
already understands. (Earlier draft proposed `H ≈ 3 days`; removed.)

**Why beyond the current cycle?** A slot's next occurrence ≥ now can land in the *next* cycle
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
handling. The **hybrid** gives direct number-pad entry *and* nudge, with one clamped binding
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
`(nearestSlot, isInCurrentCycle: Bool, currentCycleRemainingCount: Int)` so the view branches
without re-deriving cycle math.

---

## Major Model Changes

| Entity | Change |
| --- | --- |
| `Shared/AppSettings.swift` | **New** key `upcomingCommitmentCountKey` + computed `upcomingCommitmentCount` accessor (clamped ≥ 0, default 3; 0 = hide Upcoming). |
| `Shared/Scheduling/Commitment+Status.swift` | **New** helper returning the commitment's **nearest usable slot occurrence ≥ now** (`min` over its slots of each slot's next usable occurrence), with snooze + **per-cycle** saturation evaluated against each occurrence's own cycle. No horizon/scan. |
| `Shared/Scheduling/CommitmentAndSlot.swift` | **New** `stageBuckets(commitments:now:n:)` coordinator. `upcomingWithBehind` / `catchUpWithBehind` reworked into the coordinator's internals (Upcoming eligibility = has nearest usable slot; rank + `prefix(n)`; Catch-up = behind ∧ not-in-Upcoming, incl. overflow). `currentWithBehind` unchanged. |
| `Wilgo/Features/Stage/StageViewModel.swift` | `recompute()` reads `n` from `AppSettings` and calls `stageBuckets`; assigns the three lists from one result. `upcoming` property retyped to `[UpcomingEntry]`. |
| `Wilgo/Features/Stage/Upcoming.swift` | `UpcomingCommitmentRow` branches on `isInCurrentCycle`: current → time + "+k more" (k = `currentCycleRemainingCount − 1`, omit if 0); future → exact datetime + "future cycle" marker, no count. |
| `Shared/Scheduling/CommitmentAndSlot.swift` (entry type) | The Upcoming entry extends the row inputs with `isInCurrentCycle: Bool` and `currentCycleRemainingCount: Int` (a dedicated `UpcomingEntry` struct, or `WithBehind` + these fields). Current/Catch-up keep the existing `WithBehind`. |
| `Wilgo/Features/Settings/SettingsView.swift` | **New** "Stage" section: number-pad TextField + Stepper hybrid over `@AppStorage` N (clamped `0...99`), with the PRD's label + footer copy. |

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

- Add a helper returning the commitment's **nearest usable slot occurrence with `start ≥ now`**:
  the `min` over its slots of each slot's next occurrence ≥ now, keeping only usable ones
  (snooze + saturation). **Saturation is evaluated against each occurrence's own cycle**
  (resolve via `cycle.bounds(including: occurrence.start)` — do **not** count against the
  current cycle when the occurrence is in a future cycle). Returns nil if no slot has a usable
  next occurrence. No horizon, no forward scan — one candidate per slot.

**Tests:** new `WilgoTests/Commitment/CommitmentNearestSlotTests.swift`:
- nearest future occurrence crossing midnight / cycle boundary is returned (no cliff).
- min across multiple slots returns the soonest.
- snoozed / saturated next occurrence excluded; falls through to a later usable slot or nil.
- **cross-cycle saturation**: a next occurrence in the *next* cycle is saturated by *that*
  cycle's check-ins, and NOT mis-counted against the current cycle's. (Multi-cycle setup.)
- no usable next occurrence on any slot → nil.

**Depends on:** none (pure engine; parallel with Phase 1).

#### Commit 3b — `stageBuckets` coordinator + closest-N / demotion rule

**Modify:** `Shared/Scheduling/CommitmentAndSlot.swift`

- Define an `UpcomingEntry` (the row inputs + `isInCurrentCycle: Bool` +
  `currentCycleRemainingCount: Int`). Current/Catch-up keep `WithBehind`.
- Add `static func stageBuckets(commitments:now:n:) -> (current: [WithBehind], upcoming: [UpcomingEntry], catchUp: [WithBehind])` implementing the algorithm in *Architecture Summary*, using the Commit 3a nearest-usable-slot helper for Upcoming eligibility + ranking.
- For each Upcoming entry, set `isInCurrentCycle` = (nearest slot's start within
  `cycle.bounds(including: now)`) and `currentCycleRemainingCount` = `status.remainingSlots.count`.
- Rework Upcoming selection (nearest-usable-slot rank + `prefix(n)`) and Catch-up
  (behind ∧ not-in-Upcoming, including demoted overflow). `currentWithBehind` unchanged.
- Keep `nextTransitionDate` unchanged.

**Tests:** **un-comment and rewrite** `WilgoTests/Commitment/CommitmentAndSlot.swift` (currently
fully commented). New cases must cover:
- closest-N: > N future-eligible → exactly N in Upcoming, nearest first.
- < N future-eligible → all shown.
- 0 future-eligible → empty Upcoming.
- **overflow demotion**: a *behind* commitment beyond the N cutoff appears in Catch-up.
- **non-behind overflow**: beyond cutoff and not behind → appears in neither.
- priority: a behind commitment within top-N appears in Upcoming, NOT Catch-up.
- multi-slot commitment counts as 1 toward N; `currentCycleRemainingCount` reflects its
  in-cycle usable slots.
- **midnight / cross-cycle**: a usable slot in a future cycle (e.g. 7AM-tomorrow seen at 11PM
  on a daily cycle) is eligible for Upcoming (no cliff) and its entry has
  `isInCurrentCycle == false`.
- **current-cycle entry** has `isInCurrentCycle == true` and the right remaining count.
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
entry's `isInCurrentCycle`:
- **Current cycle:** render the nearest slot's time-of-day; if
  `currentCycleRemainingCount - 1 > 0`, render a small "+\(k) more" secondary label.
- **Future cycle:** render the nearest slot's **exact datetime** (via `DateFormatter` /
  `Date.formatted` — no library needed) + a clear **"future cycle"** marker; no count.
Update `#Preview`s to show: (a) current-cycle multi-slot ("+k more"), (b) future-cycle row.

The new fields (`isInCurrentCycle`, `currentCycleRemainingCount`) are produced by the engine in
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

- **Post-Commit-4 cleanup sweep (Commit 6, planned).** Once the VM uses `stageBuckets`, much of
  the old `slotKind`-based machinery is orphaned. Do this in one accurate pass *after* wiring,
  not before (avoids churning code that's about to be deleted):
  - `SlotStatusKind` consumers today are ONLY the three old `*WithBehind` helpers. After Commit 4:
    - `.beforeNextToday` — sole consumer is `upcomingWithBehind`, replaced by `stageBuckets`. Likely **deletable** (with `classifyKind`'s middle branch).
    - `.disabled` — **never read** by anyone today (only set in `status`); dead now.
    - `.noSlotToday` — still used by `catchUpWithBehind`, which the widget + `CatchUpReminder` call. Frees up only if those migrate too.
    - `.insideSlot` — still needed (Current bucket).
  - **`status()` recompute smell in `stageBuckets`:** `status(now:)` is computed 2–3× per commitment
    (inside `currentWithBehind`, the future-eligible map, and `catchUpDemoted`). Compute one
    per-commitment snapshot once and partition over it. (Negligible at Stage-sized N, but cleaner.)
  - Re-evaluate whether the old `upcomingWithBehind`/`catchUpWithBehind` can be removed or slimmed.
- **N input range:** `0...99` — floor 0 (hide Upcoming), soft ceiling 99 for the stepper/field
  hybrid; revisit if a user genuinely needs more.
