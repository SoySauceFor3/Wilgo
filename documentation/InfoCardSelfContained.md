# CommitmentHeatmapInfoCard — Self-Contained Delete + Refresh + Backfill

**Tracking:** [the history (delete + backfill) UI does not update itself automatically upon change, esp when FCR](https://app.notion.com/p/39d4b58e32c380c79194cd3a4b51469b)
**Tag:** #refactor #view

---

## Context

`CommitmentHeatmapInfoCard` renders a single period's check-in list with per-row delete and an "Add check-in" button. It is used in two places:

1. **Heatmap** — [`Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift`](../Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift): tapping a cell shows the card. Delete works; the host dismisses the card (`selectedPeriod = nil`) as a safety measure.
2. **Finished Cycle Report** — [`Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift`](../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift): the history expansion reuses the card. **Delete does not work** (no `onDelete` passed → falls back to no-op default), and the card cannot refresh itself.

### Root cause

The card renders from `period: Heatmap.PeriodData`, a **frozen value snapshot** whose `checkIns: [CheckIn]` array is captured at build time. Two problems follow:

- The snapshot never updates, so a deleted row keeps rendering unless the host rebuilds and re-passes a new `PeriodData`.
- After a SwiftData delete, the snapshot still references the now-deleted `CheckIn` (a tombstone). Reading any property on it (e.g. `checkIn.createdAt` in `checkInRow`) **crashes**. The heatmap only avoids this by immediately dismissing the card.

The FCR card has neither escape hatch: its `selectedPeriod` is `.constant(period)` (nil-ing does nothing) and it passes no `onDelete`.

### Key insight

Every field of `PeriodData` is **derivable from `commitment` + a date range** — the snapshot is purely a pre-computed cache the grid builder makes for its ~180 cells. The info card does not need the cache; it can derive everything itself and read check-ins live.

---

## Architecture Summary

Make `CommitmentHeatmapInfoCard` **self-contained**: it takes `commitment` + a date `range` and derives everything, owns its delete, refreshes itself live, and owns its own backfill sheet.

- **Live check-ins:** the card's `body` reads `commitment.checkInsInRange(startPsychDay: range.lowerBound, endPsychDay: range.upperBound)`. Because `Commitment`/`CheckIn` are SwiftData `@Model` (Observable) and `checkIns` has `inverse: \CheckIn.commitment`, deleting a check-in removes it from the relationship → the view invalidates → the row disappears. No tombstone read (we re-filter current relationship contents), no host involvement.
- **Self-delete:** the card gains `@Environment(\.modelContext)` and calls `CheckIn.delete(checkIn, from: modelContext)` directly on the confirm tap. The `onDelete` param is removed.
- **Self-backfill:** the card gains `@State private var showingBackfill` and its own `.sheet { BackfillSheet(...) }`. The `onAddCheckIn` param is removed.
- **Dismiss:** the card exposes `onDismiss: (() -> Void)?` instead of a `Binding<PeriodData?>`, fully severing its dependency on `PeriodData`. Heatmap passes `{ selectedPeriod = nil }`; FCR passes `nil`.

Derived fields (all computed in `body` from `commitment` + `range` + `rangeKind`):

| Field | Derivation |
| --- | --- |
| check-ins | `commitment.checkInsInRange(startPsychDay: range.lowerBound, endPsychDay: range.upperBound)` |
| goal | `Heatmap.expectedGoalPerPeriod(target: commitment.target, cycleKind: commitment.cycle.kind, periodKind: rangeKind)` |
| targetKind | `commitment.cycle.kind` (was a param; now derived internally) |
| isBeforeCreation | `range.upperBound < Time.startOfDay(for: commitment.createdAt)` |
| isCurrent / isFuture | date math on `range` vs `Time.startOfDay(for: Time.now())` |

### New API

```swift
CommitmentHeatmapInfoCard(
    commitment: Commitment,
    range: Range<Date>,          // [startPsychDay, endPsychDay)
    rangeKind: CycleKind,        // period granularity — how to read the range (day/week/month)
    onDismiss: (() -> Void)? = nil
)
```

Removed params: `period`, `selectedPeriod`, `onDelete`, `onAddCheckIn`, `targetKind`.
Renamed: `heatmapKind` → `rangeKind` (the second caller, FCR, isn't a heatmap; the field describes how to interpret `range`).

**Why both `range` and `rangeKind`?** They answer different questions and neither derives from the other: `range` is *which* dates (`[start, end)`); `rangeKind` is *how to read* them — label format ("Wed, Apr 7" vs "Apr 1 – Apr 7" vs "April 2026"), per-row timestamp format, and the `periodKind` for goal derivation. A 1-day `range` could be a daily cell or a 1-day custom weekly cycle; a ~30-day `range` could be monthly or a long custom cycle. Length alone can't recover the kind, so it's a genuine separate input.

---

## Design Decisions

### Derive from `commitment` + range instead of taking `PeriodData`

**Decision:** the card no longer accepts `PeriodData`. It takes `commitment` + `range` and derives check-ins, goal, isBeforeCreation, isCurrent/isFuture itself.

**Why not keep `PeriodData` and just add `@Query`?** The snapshot's `checkIns` would become vestigial and its stale-array/tombstone hazard would remain in the type. Since every field is derivable, dropping it is the honest fix rather than a workaround layered on top.

**Risk:** the heatmap grid still builds `PeriodData` for its cells (a genuine perf cache across ~180 cells) — this refactor does **not** touch the grid, only the tap → info-card handoff. Mitigation: `PeriodData` stays; only the card stops consuming it.

### Live list via `commitment.checkInsInRange` in `body` (not `@Query`)

**Decision:** re-read `commitment.checkInsInRange(...)` in `body` rather than a `@Query<CheckIn>` predicate.

**Why not `@Query`?** It reuses the exact helper the grid builders and the FCR builder use, so displayed counts can never drift from them, and there is no relationship-predicate to get wrong. Observation on the `@Model` relationship already provides live invalidation on insert/delete.

**Risk:** none material — verified below that FCR's current `cycle.checkIns` is built with the same `checkInsInRange(cycleStart, cycleEnd)` call, so switching sources produces the identical set.

### `onDismiss` callback instead of `Binding<PeriodData?>`

**Decision:** replace the `selectedPeriod` binding with `onDismiss: (() -> Void)?`.

**Why not keep the binding?** Keeping `Binding<PeriodData?>` would re-introduce the card's dependency on `PeriodData` purely for dismiss — cutting against the whole refactor. `onDismiss` lets each host decide what "tapped to close" means. Heatmap: `{ selectedPeriod = nil }`. FCR: `nil` (tap-to-dismiss inert, correct — the FCR card owns its own expand/collapse).

### Card owns the backfill sheet

**Decision:** move `BackfillSheet` presentation into the card.

**Why?** Add and delete are then handled in the same layer, and both call sites shed their `showingBackfill`/`backfillPeriod` plumbing. The "+ Add check-in" button becomes internal.

**Note:** backfill `dateRange` is clamped so the upper bound never exceeds `.now` (matching the heatmap's current `min(period.periodEndPsychDay - 1, .now)` behavior).

---

## Consistency verification (done during design)

- FCR's `cycle.checkIns` is built at [`CycleReportBuilder.swift:80`](../Wilgo/Features/Commitments/FinishedCycleReport/CycleReportBuilder.swift#L80) via `commitment.checkInsInRange(cycleStart, cycleEnd)`. The card re-deriving with the same method + `cycleStartPsychDay..<cycleEndPsychDay` yields the identical set. ✅ No count shift.
- `commitment.checkIns` relationship has `deleteRule: .cascade, inverse: \CheckIn.commitment` ([`Commitment.swift:41`](../Shared/Models/Commitment.swift#L41)) → `context.delete` removes the check-in from the relationship → Observation fires. ✅ Live refresh.

---

## Major Model Changes

None. No SwiftData model or schema change.

---

## Commit Plan

One atomic refactor. The new card signature is source-incompatible with both existing call sites, so they must change in lockstep — splitting would leave an intermediate commit that doesn't build, violating the repo's build-green-per-commit rule. Kept as a single commit for that reason.

### Commit — Make `CommitmentHeatmapInfoCard` self-contained (component + both call sites + tests)

**Modify:** [`Wilgo/Features/Commitments/SingleCommitment/Heatmap/InfoCardView.swift`](../Wilgo/Features/Commitments/SingleCommitment/Heatmap/InfoCardView.swift)

- Replace stored props `period`, `selectedPeriod`, `onDelete`, `onAddCheckIn` with:
  - `let commitment: Commitment`
  - `let range: Range<Date>`
  - `let rangeKind: CycleKind`  (was `heatmapKind`)
  - `var onDismiss: (() -> Void)? = nil`
- `targetKind` is **not** a param — add `private var targetKind: CycleKind { commitment.cycle.kind }`.
- Add `@Environment(\.modelContext) private var modelContext`.
- Add `@State private var showingBackfill = false`.
- Add derived computed props: `liveCheckIns`, `goal`, `isBeforeCreation`, `isCurrent`, `isFuture` (per the table above).
- `body` renders from `liveCheckIns`/derived props instead of `period.*`. Tap-to-dismiss calls `onDismiss?()`.
- `handleDeleteTap` confirm branch calls `CheckIn.delete(checkIn, from: modelContext)` then clears `pendingDeleteID`.
- "Add check-in" button sets `showingBackfill = true`; attach `.sheet(isPresented: $showingBackfill) { BackfillSheet(commitment: commitment, dateRange: range.lowerBound...min(range.upperBound.addingTimeInterval(-1), .now)) .presentationDetents([.medium]).presentationDragIndicator(.visible) }`.
- `periodLabel`/`checkInTimestamp` switch on `rangeKind` using `range` bounds instead of `period.*`. The `goal` visibility guard becomes `targetKind == rangeKind`.
- Rewrite `#Preview`s to the new signature (drop the `PeriodData`-wrapper previews; use the in-memory container factory to supply a live `commitment` + a range).

**Modify:** [`Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift`](../Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift)

- At the info-card call: pass `commitment: commitment`, `range: selected.periodStartPsychDay..<selected.periodEndPsychDay`, `rangeKind: heatmapKind`, `onDismiss: { selectedPeriod = nil }`. (The heatmap's local `heatmapKind` state supplies `rangeKind`; `targetKind` is no longer passed.)
- Remove the `onDelete`/`onAddCheckIn` closures and the `backfillPeriod` state + its `.sheet` (now owned by the card).

**Modify:** [`Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift`](../Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift)

- `historySection`: pass `commitment: commitment`, `range: cycle.cycleStartPsychDay..<cycle.cycleEndPsychDay`, `rangeKind: commitment.cycle.kind`, `onDismiss: nil`.
- Remove `showingBackfill` state, the `.sheet(isPresented: $showingBackfill)` modifier, and `cycleRange` (now unused). Delete now works and refreshes live.

#### Tests

Existing tests already cover the core mechanics and **survive unchanged** (they test SwiftData behavior / pure logic, not the view API):
- `WilgoTests/CheckIn/HeatmapViewDeleteTests.swift` — `deleteCheckInUpdatesCommitmentRelationship` is exactly the live-refresh guarantee this design relies on (delete → removed from `commitment.checkIns`). Also covers isolated deletion.
- `WilgoTests/CheckIn/InfoCardPendingDeleteTests.swift` — the two-tap pending-delete state machine + source labels.

**Add** to a new file `WilgoTests/CheckIn/InfoCardDerivationTests.swift` (co-located with the existing InfoCard/Heatmap tests; in-memory `ModelContainer`, strong container reference held for the whole test per repo rule) — the *new* derivation logic only:
- `liveCheckIns` (i.e. `commitment.checkInsInRange(range)`) returns exactly the check-ins whose `psychDay` is in `[range.lowerBound, range.upperBound)`, sorted by `createdAt`.
- `goal` matches `Heatmap.expectedGoalPerPeriod(target:cycleKind:periodKind:)` for representative (targetKind, rangeKind) pairs, incl. the `nil` cases.
- `isBeforeCreation` = `range.upperBound < startOfDay(createdAt)` — true just-before, false just-after the creation boundary.

> The derivation is thin (all delegates to existing tested helpers). If any piece is awkward to reach, extract a minimal `static`/free helper local to `InfoCardView.swift` so it's testable without rendering the view — but prefer testing the underlying helpers (`checkInsInRange`, `expectedGoalPerPeriod`) directly, since that's all the card calls.

**Manual verification (critical):** Launch on iPhone 17 (iOS 26.4), UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`.
1. Heatmap: tap a day with check-ins → delete one → row disappears live, no crash, card stays open showing the updated count. Tap "Add check-in" → backfill sheet opens, add one → appears live.
2. FCR: expand a failed cycle → open history → delete a check-in → **row disappears live** (this is the bug being fixed), count badge/history stay consistent. Add check-in via the card → appears live.

---

## Critical Files

| File | Role |
| --- | --- |
| `Wilgo/Features/Commitments/SingleCommitment/Heatmap/InfoCardView.swift` | The self-contained card (main change) |
| `Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift` | Heatmap call site |
| `Wilgo/Features/Commitments/FinishedCycleReport/FCRCycleCardView.swift` | FCR call site (delete bug fixed here) |
| `Shared/Models/Commitment.swift` | `checkInsInRange`, `checkIns` relationship (unchanged, relied upon) |
| `Shared/Models/CheckIn.swift` | `CheckIn.delete` (unchanged, relied upon) |

### Dependency Graph

```
Single commit: InfoCard self-contained (component + View.swift + FCRCycleCardView.swift + tests)
```

No internal ordering — the component and both call sites change together so the build stays green.
