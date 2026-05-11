# Phase 1a — Refactor `Commitment.stageStatus` Implementation Plan

**PRD:** [Notification 05/09/26](https://www.notion.so/Notification-05-09-26-35b4b58e32c38008be3eed5a40e67a6e) (Phase 1a section)
**Tracking:** [per slot start notification](https://www.notion.so/per-slot-start-notification-35b4b58e32c3801ea0e3ff3d53676b92)
**Tag:** `#stageStatusRefactor`

---

## Context

`Commitment.stageStatus(now:)` is the source of truth for Stage categorization (`metGoal`, `current`, `future`, `catchUp`, `others`). It is consumed by `CommitmentAndSlot.currentWithBehind / upcomingWithBehind / catchUpWithBehind`, which in turn feed `StageViewModel`, `NowLiveActivityManager`, and `CatchUpReminder`.

Today the function entangles two concerns: **slot mechanics** (time-deterministic — which slots are eligible at a given `now`) and **goal-progress arithmetic** (depends on the cycle's `checkIns`). Phase 1b (per-slot-start notifications) needs to *forward-project* slot eligibility to a future slot-start time independently of an uncertain future check-in count. This refactor extracts the two concerns into separately-callable functions while keeping `stageStatus` as a thin wrapper with identical observable behavior.

---

## Architecture Summary

Introduce two new functions on `Commitment`:

1. `func slotStatus(now: Date) -> SlotStatus` — pure slot mechanics. **Mode-agnostic:** always computes `remainingUsableOccurrences` over the target cycle, regardless of whether target is enabled or disabled. The previous `targetDisabledStatus` used a psych-day-only window; that was an incidental choice (no cycle-relative arithmetic happens in disabled mode), and disabled-mode consumers only read `first` and check "is there one today" — both of which are satisfied by the cycle-wide list. The wrapper's `kind` enum (`.beforeNextToday` vs `.noSlotToday`) still distinguishes the "today" question.
   - Returns a list of upcoming slots and a `kind` indicating whether `now` is *inside* a slot, *before* the next slot today, or has no slot today.
   - Still consults `checkIns` for per-slot **saturation** (a slot mechanic, not goal arithmetic). Saturation is local to a slot occurrence; it does not change the cycle-level goal calculation.

2. `func goalProgress(now: Date) -> GoalProgress` — pure cycle-level arithmetic.
   - Computes `leftToDo = max(0, target.count - checkInsInCycle.count)` for the cycle including `now`.
   - Returns `GoalProgress(leftToDo: Int?)` where `leftToDo` is `nil` when target is disabled (no meaningful "left to do" in that mode).

Reimplement `stageStatus(now:)` as a wrapper that calls both, then applies the existing precedence ladder. The wrapper has two branches based on target mode:

**Target-disabled branch** (replaces today's `targetDisabledStatus`):
```
slot.kind == .insideSlot       → .current  (behindCount 0)
slot.kind == .beforeNextToday  → .future   (behindCount 0)
slot.kind == .noSlotToday      → .others   (behindCount 0)
```

**Target-enabled branch** (replaces today's `stageStatus` body):
```
goalProgress.isMet             → .metGoal
slot.kind == .insideSlot       → .current
slot.kind == .beforeNextToday  → .future
slot.kind == .noSlotToday      → .catchUp if behindCount > 0 else .others
```

`behindCount` is derived from both halves in the enabled branch: `max(0, goalProgress.leftToDo - slotStatus.remainingSlots.count)`. In the disabled branch it is always 0. It belongs to the combined wrapper, not to either sub-function.

`targetDisabledStatus(now:)` is **deleted** — its logic is absorbed into `slotStatus` (slot window choice) and the wrapper's target-disabled branch (kind → category map).

This is a **structure-only refactor.** No call site changes its behavior; no test changes its expectation. All existing tests pass without modification.

---

## Design Decisions

### Absorb `targetDisabledStatus` into the same refactor; `slotStatus` is mode-agnostic

**Decision:** Delete the private `targetDisabledStatus(now:)` helper. `slotStatus(now:)` always builds the remaining-slots list over the target cycle, regardless of target mode. The wrapper's target-disabled branch maps `kind → category` without consulting goal progress.

**Why not keep the psych-day window in disabled mode?** Today's `targetDisabledStatus` happens to use a psych-day window, but disabled-mode consumers only read `first` (for `.current`/`.future` rendering) and check "is there one today" (already encoded in `kind`). The cycle window is a strict superset of what they read, so the behavior is unchanged. Unifying the window removes a parallel "compute remaining + classify" code path.

**Risk:** Behavioral drift in target-disabled cases. Mitigation: existing `CommitmentTargetDisableTests` exercises this path and must pass with zero modification; Commit 4's parity test adds explicit target-disabled scenarios.

### Saturation stays in `slotStatus`, not `goalProgress`

**Decision:** `slotStatus` continues to consult `checkIns` for `Slot.isSaturated(at:checkIns:)`. `goalProgress` only consults `checkIns` for cycle-level counting.

**Why not carve saturation out into a third function?** Saturation is a property of a single slot occurrence (e.g., "has this slot already been used"), not of cycle-level progress. It is part of "is this slot still eligible at time `now`," which is what `slotStatus` is for. Carving it out would split slot mechanics across two functions for no Phase-1b benefit.

**Risk:** Phase 1b's forward projection of `slotStatus(now: futureSlotStart)` will still depend on `checkIns`-known-now via saturation, which is the same drift the PRD already accepts. Mitigation: the three-layer alignment mechanism (forward projection + refresh on events + `willPresent` swallow) covers this.

### Keep `stageStatus` as the public API for now

**Decision:** All existing callers of `stageStatus` are left as-is. New callers (Phase 1b's scheduler) will use `slotStatus` / `goalProgress` directly.

**Why not migrate `CommitmentAndSlot.currentWithBehind` et al. to the split API?** They want category + behind + slots together — that's exactly what `stageStatus` returns. Migrating them would mean each call site re-implementing the precedence ladder, which duplicates logic and increases regression risk. Better to leave `stageStatus` as the bundled API and let new callers cherry-pick the halves they need.

**Risk:** Two parallel APIs (`stageStatus` and `slotStatus + goalProgress`) could drift over time. Mitigation: `stageStatus` is reimplemented in terms of the new functions, so they cannot diverge — any change to the underlying logic flows through both views.

### Place new types alongside existing `StageStatus`

**Decision:** `SlotStatus`, `GoalProgress`, and any sub-categories are declared inside `extension Commitment` in `Shared/Models/Commitment.swift`, next to `StageStatus` and `StageCategory`. No new files.

**Why not new files (e.g., `SlotStatus.swift`)?** Stage-related types are tightly coupled to `Commitment` and currently colocated. Splitting them adds navigation cost without modularity gain. If the file grows uncomfortably, that's a separate cleanup.

---

## Major Model Changes

| Entity                           | Change                                                                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Shared/Models/Commitment.swift` | Add `SlotStatus`, `SlotStatusKind`, `GoalProgress` types. Add `slotStatus(now:)` and `goalProgress(now:)`. Reimplement `stageStatus(now:)` as a wrapper. |

No persisted-schema changes. No new files in production code. New test file in `WilgoTests/Commitment/`.

---

## Proposed types and signatures

```swift
extension Commitment {
    enum SlotStatusKind {
        case insideSlot          // now ∈ [slot.start, slot.end] for some remainingSlot
        case beforeNextToday     // first remainingSlot is later today
        case noSlotToday         // no remainingSlot starts today
    }

    struct SlotStatus {
        let kind: SlotStatusKind
        /// Same list `stageStatus` builds today via `remainingUsableOccurrences`,
        /// over the target cycle (or psych day when target is disabled).
        let remainingSlots: [Slot]
    }

    struct GoalProgress {
        /// max(0, target.count - checkInsInCycle.count). Nil when target is disabled
        /// (no meaningful "left to do" exists in that mode).
        let leftToDo: Int?
        /// True when `leftToDo == 0`. False when `leftToDo` is nil (disabled) or > 0.
        var isMet: Bool { leftToDo == 0 }
    }

    func slotStatus(now: Date = Time.now()) -> SlotStatus { ... }
    func goalProgress(now: Date = Time.now()) -> GoalProgress { ... }
}
```

`stageStatus(now:)` becomes:

```swift
func stageStatus(now: Date = Time.now()) -> StageStatus {
    let nowPsychDay = Time.startOfDay(for: now)
    let slot = slotStatus(now: now)

    if case .disabled = target.effectiveMode(on: nowPsychDay) {
        // Target-disabled: no goal progress, no behindCount. Map kind directly.
        let category: StageCategory = {
            switch slot.kind {
            case .insideSlot: return .current
            case .beforeNextToday: return .future
            case .noSlotToday: return .others
            }
        }()
        return StageStatus(category: category, nextUpSlots: slot.remainingSlots, behindCount: 0)
    }

    let progress = goalProgress(now: now)
    if progress.isMet {
        return StageStatus(category: .metGoal, nextUpSlots: [], behindCount: 0)
    }
    // Past here, target is enabled and progress.leftToDo is non-nil and > 0.
    let leftToDo = progress.leftToDo ?? 0
    let behindCount = max(0, leftToDo - slot.remainingSlots.count)

    switch slot.kind {
    case .insideSlot:
        return StageStatus(category: .current, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
    case .beforeNextToday:
        return StageStatus(category: .future, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
    case .noSlotToday:
        let category: StageCategory = behindCount > 0 ? .catchUp : .others
        return StageStatus(category: category, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
    }
}
```

**Important:** `slotStatus(now:)` itself checks `target.effectiveMode` to pick the right window (psych-day for disabled, cycle for enabled). The wrapper checks `target.effectiveMode` only to pick between the two classification branches. The dual check is intentional and cheap — keeps each function's responsibility clear (slotStatus picks slots; the wrapper picks category).

`targetDisabledStatus(now:)` is **deleted** in Commit 3.

---

## Commit Plan

### Phase 1a — `stageStatus` refactor

Goal: extract `slotStatus` and `goalProgress` from `stageStatus`, preserving observable behavior.

#### Commit 1 — add `GoalProgress` and `goalProgress(now:)`

**Modify:** `Shared/Models/Commitment.swift`

- Add `GoalProgress` struct with `leftToDo: Int?` and computed `isMet: Bool` (true iff `leftToDo == 0`).
- Add `func goalProgress(now: Date = Time.now()) -> GoalProgress` that replicates the `leftToDo` calculation currently inside `stageStatus`:
  - When `target.effectiveMode(on: nowPsychDay) == .disabled`, return `GoalProgress(leftToDo: nil)` — there is no meaningful "left to do" in disabled mode, and `isMet` will be false (matching today's behavior where target-disabled commitments are never `.metGoal`).
  - Otherwise: same `startDay`/`endDay`/`checkInsInCycle`/`leftToDo` calculation as today.
- **Do not** change `stageStatus` yet.

**Create:** `WilgoTests/Commitment/CommitmentGoalProgressTests.swift`

Tests (each builds a `Commitment` with explicit `checkIns`, cycle, target):

- `goalProgress_emptyCheckIns_leftToDoEqualsTarget`
- `goalProgress_someCheckIns_leftToDoIsDifference`
- `goalProgress_overTarget_leftToDoIsZero` (more check-ins than target → `leftToDo == 0`, `isMet == true`)
- `goalProgress_exactlyMet_isMetTrue`
- `goalProgress_targetDisabled_leftToDoIsNil_isMetFalse`
- `goalProgress_checkInsOutsideCycle_notCounted`
- `goalProgress_differentNow_recomputesForCorrectCycle` (two `now` values landing in different cycles)

**Verification:** `xcodebuild test` with `-only-testing:WilgoTests/CommitmentGoalProgressTests` passes. Existing tests still pass.

#### Commit 2 — add `SlotStatus`/`SlotStatusKind` and `slotStatus(now:)`

**Modify:** `Shared/Models/Commitment.swift`

- Add `SlotStatusKind` enum (`insideSlot`, `beforeNextToday`, `noSlotToday`) and `SlotStatus` struct (`kind`, `remainingSlots: [Slot]`).
- Add `func slotStatus(now: Date = Time.now()) -> SlotStatus`:
  - Build `remainingUsableOccurrences` over the full target cycle. Mode-agnostic — no branch on `target.effectiveMode`.
  - Classify `kind`:
    - If `remainingSlots.first?.start <= now` → `.insideSlot`.
    - Else if any `remainingSlot.start < todayEnd` (next psych day boundary) → `.beforeNextToday`.
    - Else → `.noSlotToday`.
- **Do not** change `stageStatus` or delete `targetDisabledStatus` yet (Commit 3 does that).

**Create:** `WilgoTests/Commitment/CommitmentSlotStatusTests.swift`

Tests:

- `slotStatus_nowInsideSlot_kindIsInsideSlot_remainingIncludesCurrentSlot`
- `slotStatus_nowBeforeFirstSlotToday_kindIsBeforeNextToday`
- `slotStatus_allSlotsTodayPassed_kindIsNoSlotToday`
- `slotStatus_currentSlotSnoozed_excludedFromRemaining` (verify snooze still filters)
- `slotStatus_currentSlotSaturatedByCheckIns_excludedFromRemaining` (verify saturation still filters)
- `slotStatus_targetDisabled_returnsCycleRemaining_sameAsEnabled` (mode-agnostic: same window in both modes)
- `slotStatus_forwardProjection_futureNow_returnsFutureSlots` (call with `now = futureDate` — confirms forward-projection works, which is what Phase 1b needs)
- `slotStatus_carryOverSlot_includedWhenSpanningMidnight` (verify `includeCarryOver` path)

**Verification:** `xcodebuild test` with `-only-testing:WilgoTests/CommitmentSlotStatusTests` passes. Existing tests still pass.

#### Commit 3 — reimplement `stageStatus(now:)` in terms of `slotStatus` and `goalProgress`

**Modify:** `Shared/Models/Commitment.swift`

- Replace the body of `stageStatus(now:)` with the wrapper shown in "Proposed types and signatures" above.
- Delete the private helper `targetDisabledStatus(now:)`. Its logic is now absorbed by `slotStatus` (window choice) and the wrapper's target-disabled branch (kind → category mapping).
- No new tests in this commit — the safety net is the existing `stageStatus` test suite (`CommitmentStageSnoozeTests`, `CommitmentStageWholeDayTests`, `CommitmentTargetDisableTests`, `CommitmentInspirationOnlyStageTests`, `CommitmentSlotCapacityStageTests`, `CommitmentRemindersDisableTests`).

**Verification:**

- `xcodebuild test` with `-only-testing:WilgoTests/CommitmentStageSnoozeTests` (and the other five stage test files) — all must pass with **zero** modifications. CLAUDE.md notes `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()` was already failing before this work; that one's failure is unchanged.
- Full test suite via `./test-with-cleanup.sh` to confirm no regressions in downstream consumers (`CommitmentAndSlot`, `StageViewModel`, etc.).

#### Commit 4 — parity test for `stageStatus` wrapper

**Create:** `WilgoTests/Commitment/CommitmentStageStatusParityTests.swift`

A focused parity test that confirms `stageStatus(now:)` produces the expected `(category, behindCount, nextUpSlots-equivalent)` for representative scenarios:

- All five categories (`metGoal`, `current`, `future`, `catchUp`, `others`) for an enabled-target commitment.
- Target disabled, slot-in-window → `.current`.
- Target disabled, no slot today → `.others`.
- Cross-check: for each scenario, also call `slotStatus` and `goalProgress` and assert the wrapper's outputs match the documented derivation (`behindCount = max(0, leftToDo - remainingSlots.count)`, etc.).

These act as a regression net for the wrapper specifically. Existing tests cover behavior; this one documents the *contract* between the three functions.

**Verification:** new test file passes; full suite still green.

---

## Critical Files

| File                                                            | Role                                              |
| --------------------------------------------------------------- | ------------------------------------------------- |
| `Shared/Models/Commitment.swift`                                | Add `slotStatus`, `goalProgress`; rewrap `stageStatus` |
| `WilgoTests/Commitment/CommitmentGoalProgressTests.swift` (new) | Unit tests for goal arithmetic                    |
| `WilgoTests/Commitment/CommitmentSlotStatusTests.swift` (new)   | Unit tests for slot mechanics, incl. forward projection |
| `WilgoTests/Commitment/CommitmentStageStatusParityTests.swift` (new) | Wrapper contract test                        |

### Dependency Graph

```
Commit 1 (goalProgress)        Commit 2 (slotStatus)
       \                              /
        \                            /
         +---- Commit 3 (rewrap stageStatus) ----+
                                                 |
                                                 +-- Commit 4 (parity test)
```

Commits 1 and 2 are independent and can be parallelized. Commit 3 depends on both. Commit 4 depends on Commit 3.

---

## Manual verification

None required for Phase 1a. This is a pure refactor with no UI, persistence, or notification surface changes. The full test suite is the verification.

---

## Out of scope (deferred to Phase 1b and beyond)

- Any caller migrating from `stageStatus` to `slotStatus` + `goalProgress`.
- Forward-projection logic for notification scheduling (Phase 1b uses these APIs but isn't built here).
- Renaming or relocating `StageStatus`, `StageCategory`, or related types.
- Carving slot saturation into its own function.
