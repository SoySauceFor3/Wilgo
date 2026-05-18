# Remove stageStatus Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** N/A  
**Tracking:** [allow user to choose for a specific commitment, show the reminders keep showing after the goal is met](https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link) (prerequisite refactor)  
**Tag:** `#RemoveStageStatus`

---

## Context

`stageStatus(now:)` on `Commitment` is a thin wrapper that combines `slotStatus(now:)` + `goalProgress(now:)` into a `StageStatus` struct (with a `StageCategory` enum). The `.metGoal` category encodes a *display preference* (hide this commitment) directly into model logic, which causes awkwardness: the upcoming `continueRemindersAfterGoalMet` feature needs to fight against this baked-in precedence rule.

This refactor deletes `stageStatus`, `StageStatus`, and `StageCategory` from the model, and rewires all consumers to use `slotStatus` + `goalProgress` directly.

---

## Architecture Summary

`CommitmentAndSlot` — the main consumer — currently calls `stageStatus` and pattern-matches on `.category`. After this refactor it will call `slotStatus` + `goalProgress` directly and apply its own category logic inline. `StageViewModel` already pre-filters on `isRemindersEnabled` before passing to `CommitmentAndSlot`; it gains a second filter for goal-met exclusion (the behavior that was previously implicit inside `stageStatus`). Tests currently asserting on `StageCategory` are rewritten to assert on `slotStatus.kind` + `goalProgress` directly.

`stageStatus` / `StageStatus` / `StageCategory` are **only** used in `CommitmentAndSlot` and tests — nowhere in the widget, SwiftUI views, or notification schedulers — making this a contained refactor.

---

## Design Decisions

### `behindCount` computation — keep in CommitmentAndSlot or extract?

**Decision:** Inline it in each `CommitmentAndSlot` function. It's a one-liner (`max(0, leftToDo - remainingSlots.count)`) and only needed there.

**Why not a new helper on `Commitment`?** We just removed one wrapper from the model. Adding another would repeat the same mistake at a finer granularity.

### What about `nextUpSlots` from StageStatus?

`StageStatus.nextUpSlots` came from `slotStatus.remainingSlots`. After this refactor, `CommitmentAndSlot` reads `slotStatus.remainingSlots` directly — no information is lost.

### Goal-met filtering — in CommitmentAndSlot or StageViewModel?

**Decision:** `StageViewModel` gains the goal-met filter (same single-line filter already used for `isRemindersEnabled`). `CommitmentAndSlot` functions stop receiving goal-met commitments altogether — they no longer need to handle that case. This is cleaner: `CommitmentAndSlot` maps commitment → (slots, behindCount) without any exclusion logic; exclusion is the caller's job.

---

## Major Model Changes

| Entity | Change |
|--------|--------|
| `Shared/Models/Commitment.swift` | Delete `StageCategory`, `StageStatus`, `stageStatus(now:)` |
| `Shared/Scheduling/CommitmentAndSlot.swift` | Replace `stageStatus` calls with `slotStatus` + `goalProgress` inline |
| `Wilgo/Features/Stage/StageViewModel.swift` | Add goal-met pre-filter before passing to `CommitmentAndSlot` |
| `WilgoTests/Commitment/CommitmentStageStatusParityTests.swift` | Rewrite: assert on `slotStatus` + `goalProgress` directly; drop `.metGoal` assertions |
| `WilgoTests/Commitment/CommitmentTargetDisableTests.swift` | Replace `stageStatus` category assertions with `slotStatus.kind` |
| `WilgoTests/Commitment/CommitmentStageSnoozeTests.swift` | Replace `stageStatus` category assertions with `slotStatus.kind` + `remainingSlots` |
| `WilgoTests/Commitment/CommitmentStageWholeDayTests.swift` | Replace `stageStatus` calls with `slotStatus` |
| `WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift` | Replace `stageStatus` with `slotStatus` + `goalProgress` |
| `WilgoTests/Commitment/CommitmentInspirationOnlyStageTests.swift` | Replace `stageStatus` with `slotStatus` + `goalProgress` |
| `WilgoTests/Commitment/CommitmentRemindersDisableTests.swift` | Update the one `stageStatus` call |

---

## Commit Plan

### Phase 1 — Rewrite CommitmentAndSlot (no model deletion yet)

This commit rewrites `CommitmentAndSlot` to use `slotStatus` + `goalProgress` directly, while `stageStatus` still exists in the model. This lets us verify the behavioral equivalence before deleting anything.

#### Commit 1 — Rewrite CommitmentAndSlot to use slotStatus + goalProgress directly

**Modify:** `Shared/Scheduling/CommitmentAndSlot.swift`

Replace the entire file content with:

```swift
import Foundation

enum CommitmentAndSlot {
    /// Shared tuple used by Stage to render rows with behind information.
    typealias WithBehind = (commitment: Commitment, slots: [Slot], behindCount: Int)

    static func currentWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            let slot = commitment.slotStatus(now: now)
            guard slot.kind == .insideSlot else { return nil }
            let behindCount = computeBehindCount(commitment: commitment, slotStatus: slot, now: now)
            return (commitment: commitment, slots: slot.remainingSlots, behindCount: behindCount)
        }
        return result.sorted {
            $0.slots[0].remainingFraction(at: now) < $1.slots[0].remainingFraction(at: now)
        }
    }

    static func upcomingWithBehind(
        commitments: [Commitment],
        after time: Date
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            let slot = commitment.slotStatus(now: time)
            guard slot.kind == .beforeNextToday else { return nil }
            let behindCount = computeBehindCount(commitment: commitment, slotStatus: slot, now: time)
            return (commitment: commitment, slots: slot.remainingSlots, behindCount: behindCount)
        }
        return result.sorted {
            guard let lhs = $0.slots.first, let rhs = $1.slots.first else { return false }
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
    }

    static func catchUpWithBehind(
        commitments: [Commitment],
        now: Date = Time.now()
    ) -> [WithBehind] {
        let result: [WithBehind] = commitments.compactMap { commitment in
            let slot = commitment.slotStatus(now: now)
            guard slot.kind == .noSlotToday else { return nil }
            let progress = commitment.goalProgress(now: now)
            guard let leftToDo = progress.leftToDo, leftToDo > 0 else { return nil }
            let behindCount = max(0, leftToDo - slot.remainingSlots.count)
            guard behindCount > 0 else { return nil }
            return (commitment: commitment, slots: slot.remainingSlots, behindCount: behindCount)
        }
        return result.sorted { lhs, rhs in
            let lhsTargetCount = max(lhs.commitment.target.count, 1)
            let rhsTargetCount = max(rhs.commitment.target.count, 1)
            let lhsUrgency = Double(lhs.behindCount) / Double(lhsTargetCount)
            let rhsUrgency = Double(rhs.behindCount) / Double(rhsTargetCount)
            if lhsUrgency != rhsUrgency { return lhsUrgency > rhsUrgency }
            if lhs.commitment.target.count != rhs.commitment.target.count {
                return lhs.commitment.target.count > rhs.commitment.target.count
            }
            guard let lhsSlot = lhs.slots.first, let rhsSlot = rhs.slots.first else {
                if lhs.slots.isEmpty, !rhs.slots.isEmpty { return false }
                if !lhs.slots.isEmpty, rhs.slots.isEmpty { return true }
                return false
            }
            if lhsSlot.start == rhsSlot.start { return lhsSlot.end < rhsSlot.end }
            return lhsSlot.start < rhsSlot.start
        }
    }

    /// Earliest upcoming windowStart, windowEnd, or psychDay boundary across all commitments' slots.
    static func nextTransitionDate(
        commitments: [Commitment], now: Date = Time.now()
    ) -> Date? {
        var candidates: [Date] = []
        for commitment in commitments {
            for slot in commitment.slots {
                let start = slot.startToday
                let end = slot.endToday
                if start > now { candidates.append(start) }
                if end > now { candidates.append(end) }
            }
        }
        let currentPsychDayBase = Time.startOfDay(for: now)
        if let nextPsychDayBase = Time.calendar.date(
            byAdding: .day, value: 1, to: currentPsychDayBase)
        {
            if nextPsychDayBase > now { candidates.append(nextPsychDayBase) }
        }
        return candidates.min()
    }

    // MARK: - Private

    private static func computeBehindCount(
        commitment: Commitment,
        slotStatus: Commitment.SlotStatus,
        now: Date
    ) -> Int {
        let progress = commitment.goalProgress(now: now)
        guard let leftToDo = progress.leftToDo else { return 0 }
        return max(0, leftToDo - slotStatus.remainingSlots.count)
    }
}
```

**Key behavioral note for `catchUpWithBehind`:** The old version matched on `.catchUp` category which already encoded `behindCount > 0 && noSlotToday`. The new version makes both conditions explicit: `kind == .noSlotToday` AND `behindCount > 0`. Target-disabled commitments (`leftToDo == nil`) return `nil` and are excluded — same as before since they never got `.catchUp`.

**Modify:** `Wilgo/Features/Stage/StageViewModel.swift`

Replace `recompute()` to add goal-met pre-filter (this replaces the filtering that `stageStatus` did implicitly via `.metGoal`):

```swift
private func recompute() {
    let now = Date()
    let remindersOn = lastCommitments.filter(\.isRemindersEnabled)
    let stageActive = remindersOn.filter { !$0.goalProgress(now: now).isMet }
    current = CommitmentAndSlot.currentWithBehind(commitments: stageActive, now: now)
    upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: stageActive, after: now)
    catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: stageActive, now: now)
}
```

- [ ] **Step 1: Implement CommitmentAndSlot + StageViewModel changes** (as above)

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests**

```bash
./test-with-cleanup.sh 2>&1 | tail -40
```
Expected: all previously passing tests still pass. (`CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence` is a known pre-existing failure — do not count it.)

- [ ] **Step 4: Commit**

```bash
git add Shared/Scheduling/CommitmentAndSlot.swift \
        Wilgo/Features/Stage/StageViewModel.swift
git commit -m "$(cat <<'EOF'
Rewrite CommitmentAndSlot to use slotStatus+goalProgress directly

Removes the stageStatus wrapper from the hot path. StageViewModel
gains an explicit goal-met pre-filter that was previously implicit
inside stageStatus returning .metGoal.

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 2 — Delete stageStatus from model

#### Commit 2 — Delete StageCategory, StageStatus, stageStatus from Commitment

**Modify:** `Shared/Models/Commitment.swift`

Delete the following from the `// MARK: - Stage categorization` section (lines ~138–365):
- `enum StageCategory { ... }` 
- `struct StageStatus { ... }`
- `func stageStatus(now:) -> StageStatus { ... }`

Keep `GoalProgress`, `SlotStatusKind`, `SlotStatus`, `slotStatus(now:)`, `goalProgress(now:)` — these are the primitives we're keeping.

The section to delete starts at `// MARK: - Stage categorization` and ends after the closing `}` of `func stageStatus`. The `// MARK: - Slot queries` section and all private helpers stay.

- [ ] **Step 1: Delete StageCategory, StageStatus, stageStatus from Commitment.swift**

- [ ] **Step 2: Build**

```bash
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' 2>&1 | grep -E "error:|BUILD"
```
Expected: BUILD SUCCEEDED (or only test-file compile errors, since tests still reference `stageStatus`).

- [ ] **Step 3: Commit**

```bash
git add Shared/Models/Commitment.swift
git commit -m "$(cat <<'EOF'
Delete StageCategory, StageStatus, stageStatus from Commitment model

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 3 — Migrate tests

Each test file is an independent commit. They can be parallelized after Commit 2.

#### Commit 3 — Rewrite CommitmentStageStatusParityTests

The parity tests already test `slotStatus` + `goalProgress` directly in the cross-check section — those stay. The upper section currently asserts on `stageStatus.category`; rewrite to assert on `slotStatus.kind` + `goalProgress.isMet` + `behindCount`.

**Modify:** `WilgoTests/Commitment/CommitmentStageStatusParityTests.swift`

Replace the entire file with:

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentStageStatusParityTests {
    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int)],
        targetCount: Int = 3,
        targetMode: TargetMode = .on,
        cycleKind: CycleKind = .daily,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map { Slot(start: tod(hour: $0.start), end: tod(hour: $0.end)) }
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount, mode: targetMode)
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - Enabled-target scenarios

    @Test("enabled + goal met → goalProgress.isMet, slotStatus still reflects slot reality")
    @MainActor func enabled_goalMet_progressIsMetSlotStillReflectsReality() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 2, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let progress = c.goalProgress(now: now)
        let slot = c.slotStatus(now: now)

        #expect(progress.isMet == true)
        #expect(progress.leftToDo == 0)
        // slotStatus is unaffected — the slot window is still open
        #expect(slot.kind == .insideSlot)
    }

    @Test("enabled + slot active now, goal not met → insideSlot, goalProgress not met")
    @MainActor func enabled_slotActive_goalNotMet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .insideSlot)
        #expect(!slot.remainingSlots.isEmpty)
        #expect(slot.remainingSlots.first!.start <= now)
        #expect(progress.isMet == false)
    }

    @Test("enabled + slot starts later today, goal not met → beforeNextToday")
    @MainActor func enabled_slotFutureToday_goalNotMet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(14, 16)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .beforeNextToday)
        #expect(!slot.remainingSlots.isEmpty)
        #expect(slot.remainingSlots.first!.start > now)
        #expect(progress.isMet == false)
    }

    @Test("enabled + no slot today, leftToDo > remainingSlots → noSlotToday, behindCount > 0")
    @MainActor func enabled_noSlotToday_behindNeeded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, cycleKind: .daily, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .noSlotToday)
        let leftToDo = try #require(progress.leftToDo)
        let behindCount = max(0, leftToDo - slot.remainingSlots.count)
        #expect(behindCount > 0)
    }

    @Test("enabled + no slot today, leftToDo <= remainingSlots in weekly cycle → noSlotToday, behindCount 0")
    @MainActor func enabled_noSlotToday_sufficientRemaining() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 1, cycleKind: .weekly, in: ctx)

        let now = date(year: 2026, month: 1, day: 1, hour: 18)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .noSlotToday)
        let leftToDo = try #require(progress.leftToDo)
        let behindCount = max(0, leftToDo - slot.remainingSlots.count)
        #expect(behindCount == 0)
    }

    // MARK: - Target-disabled scenarios

    @Test("disabled + slot active now → insideSlot, goalProgress nil (no leftToDo)")
    @MainActor func disabled_slotActive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .insideSlot)
        #expect(progress.leftToDo == nil)
        #expect(progress.isMet == false)
    }

    @Test("disabled + slot future today → beforeNextToday")
    @MainActor func disabled_slotFutureToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(15, 17)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .beforeNextToday)
        #expect(!slot.remainingSlots.isEmpty)
        #expect(progress.leftToDo == nil)
    }

    @Test("disabled + no slot today → noSlotToday")
    @MainActor func disabled_noSlotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .noSlotToday)
        #expect(progress.leftToDo == nil)
    }

    // MARK: - behindCount derivation cross-checks

    @Test("behindCount derivation: enabled current")
    @MainActor func behindCount_enabledCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .insideSlot)
        #expect(progress.isMet == false)
        let leftToDo = try #require(progress.leftToDo)
        let behindCount = max(0, leftToDo - slot.remainingSlots.count)
        #expect(behindCount == 2)
    }

    @Test("behindCount derivation: enabled catchUp")
    @MainActor func behindCount_enabledCatchUp() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetCount: 3, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .noSlotToday)
        #expect(progress.isMet == false)
        let leftToDo = try #require(progress.leftToDo)
        let behindCount = max(0, leftToDo - slot.remainingSlots.count)
        #expect(behindCount == 3)
    }

    @Test("behindCount derivation: disabled → always 0")
    @MainActor func behindCount_disabled() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11)], targetMode: .disabled, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 18)
        let slot = c.slotStatus(now: now)
        let progress = c.goalProgress(now: now)

        #expect(slot.kind == .noSlotToday)
        #expect(progress.leftToDo == nil)
        // disabled → no behindCount concept
    }
}
```

- [ ] **Step 1: Replace CommitmentStageStatusParityTests.swift** (as above)

- [ ] **Step 2: Run the file's tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentStageStatusParityTests 2>&1 | tail -30
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentStageStatusParityTests.swift
git commit -m "$(cat <<'EOF'
Rewrite CommitmentStageStatusParityTests: assert slotStatus+goalProgress directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

#### Commit 4 — Update CommitmentTargetDisableTests (parallel with 3, 5, 6, 7, 8)

**Modify:** `WilgoTests/Commitment/CommitmentTargetDisableTests.swift`

For each test that calls `c.stageStatus(now: now)`, replace with `c.slotStatus(now: now)` and `c.goalProgress(now: now)`, then update assertions:

| Old assertion | New assertion |
|---|---|
| `status.category == .current` | `slot.kind == .insideSlot` |
| `status.category == .future` | `slot.kind == .beforeNextToday` |
| `status.category == .others` | `slot.kind == .noSlotToday && (goalProgress.leftToDo == nil \|\| behindCount == 0)` |
| `status.category != .metGoal` | `goalProgress.isMet == false` |
| `status.behindCount == 0` | `max(0, (goalProgress.leftToDo ?? 0) - slot.remainingSlots.count) == 0` |
| `status.nextUpSlots.isEmpty` | `slot.remainingSlots.isEmpty` |
| `status.nextUpSlots.allSatisfy { $0.start > now }` | `slot.remainingSlots.allSatisfy { $0.start > now }` |
| `!status.nextUpSlots.isEmpty` | `!slot.remainingSlots.isEmpty` |

- [ ] **Step 1: Apply the substitutions** to `CommitmentTargetDisableTests.swift`

- [ ] **Step 2: Run the file's tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentTargetDisableTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentTargetDisableTests.swift
git commit -m "$(cat <<'EOF'
Update CommitmentTargetDisableTests: use slotStatus+goalProgress directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

#### Commit 5 — Update CommitmentStageSnoozeTests (parallel with 3, 4, 6, 7, 8)

**Modify:** `WilgoTests/Commitment/CommitmentStageSnoozeTests.swift`

Apply the same substitution table as Commit 4. All assertions on `status.category`, `status.nextUpSlots`, and `status.behindCount` become `slot.kind`, `slot.remainingSlots`, and the inline `behindCount` formula.

- [ ] **Step 1: Apply substitutions** to `CommitmentStageSnoozeTests.swift`

- [ ] **Step 2: Run the file's tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentStageSnoozeTests 2>&1 | tail -20
```
Expected: all tests pass except the known pre-existing failure (`stageStatus_snoozeDoesNotAffectFutureOccurrence`), which will also need its `stageStatus` call updated but may still fail for its pre-existing reason.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentStageSnoozeTests.swift
git commit -m "$(cat <<'EOF'
Update CommitmentStageSnoozeTests: use slotStatus+goalProgress directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

#### Commit 6 — Update CommitmentStageWholeDayTests (parallel with 3, 4, 5, 7, 8)

**Modify:** `WilgoTests/Commitment/CommitmentStageWholeDayTests.swift`

Apply same substitution table. All `status.nextUpSlots` become `slot.remainingSlots`.

- [ ] **Step 1: Apply substitutions**

- [ ] **Step 2: Run the file's tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentStageWholeDayTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentStageWholeDayTests.swift
git commit -m "$(cat <<'EOF'
Update CommitmentStageWholeDayTests: use slotStatus directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

#### Commit 7 — Update CommitmentSlotCapacityStageTests (parallel with 3, 4, 5, 6, 8)

**Modify:** `WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift`

The `.metGoal` assertion (`status.category == .metGoal`) becomes `goalProgress.isMet == true`. Apply substitution table for all other assertions.

- [ ] **Step 1: Apply substitutions**

- [ ] **Step 2: Run the file's tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentSlotCapacityStageTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift
git commit -m "$(cat <<'EOF'
Update CommitmentSlotCapacityStageTests: use slotStatus+goalProgress directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

#### Commit 8 — Update remaining test files (parallel with 3, 4, 5, 6, 7)

**Modify:** `WilgoTests/Commitment/CommitmentInspirationOnlyStageTests.swift`

- `status.behindCount == 1` → compute inline: `let leftToDo = try #require(progress.leftToDo); #expect(max(0, leftToDo - slot.remainingSlots.count) == 1)`
- `status.category == .metGoal` → `#expect(progress.isMet == true)`

**Modify:** `WilgoTests/Commitment/CommitmentRemindersDisableTests.swift`

- `c.stageStatus(now: now).category == .current` → `c.slotStatus(now: now).kind == .insideSlot`

- [ ] **Step 1: Apply substitutions to both files**

- [ ] **Step 2: Run the affected tests**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/CommitmentInspirationOnlyStageTests \
  -only-testing WilgoTests/CommitmentRemindersDisableTests 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add WilgoTests/Commitment/CommitmentInspirationOnlyStageTests.swift \
        WilgoTests/Commitment/CommitmentRemindersDisableTests.swift
git commit -m "$(cat <<'EOF'
Update remaining stage tests: use slotStatus+goalProgress directly

#RemoveStageStatus
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 4 — Final verification

#### Commit 9 — Run full test suite and verify clean build

- [ ] **Step 1: Run full test suite**

```bash
./test-with-cleanup.sh 2>&1 | tail -40
```
Expected: all previously passing tests pass. The known pre-existing failure (`CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence`) may still appear — do not count it.

- [ ] **Step 2: Confirm stageStatus is fully gone**

```bash
grep -rn "stageStatus\|StageStatus\|StageCategory\|\.metGoal" \
  Shared/ Wilgo/ WilgoTests/ WidgetExtension/ --include="*.swift"
```
Expected: zero results (or only comments in documentation).

No new commit needed for this step — it's a verification gate before the feature work begins.

---

## Critical Files

| File | Role |
|------|------|
| `Shared/Models/Commitment.swift` | Delete `StageCategory`, `StageStatus`, `stageStatus` |
| `Shared/Scheduling/CommitmentAndSlot.swift` | Core consumer rewrite |
| `Wilgo/Features/Stage/StageViewModel.swift` | Add goal-met pre-filter |
| 6 test files | Migrate `stageStatus` assertions → `slotStatus` + `goalProgress` |

---

## Dependency Graph

```
Commit 1: Rewrite CommitmentAndSlot + StageViewModel (behavioral parity)
    |
    +-- Commit 2: Delete stageStatus from model [after 1]
            |
            +-- Commit 3: Rewrite CommitmentStageStatusParityTests  [parallel after 2]
            +-- Commit 4: Update CommitmentTargetDisableTests       [parallel after 2]
            +-- Commit 5: Update CommitmentStageSnoozeTests         [parallel after 2]
            +-- Commit 6: Update CommitmentStageWholeDayTests       [parallel after 2]
            +-- Commit 7: Update CommitmentSlotCapacityStageTests   [parallel after 2]
            +-- Commit 8: Update remaining test files               [parallel after 2]
                    |
                    (all 3–8 must pass before final verification)
                    |
                    +-- Commit 9: Full suite verification [after all of 3-8]
```

Commits 3–8 are fully independent of each other and can be parallelized after Commit 2.
