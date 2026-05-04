# Slot Capacity (Per-slot Max Check-ins) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** [cool-off / gap type commitment](https://www.notion.so/cool-off-gap-type-commitment-3564b58e32c38009a7bbe5041a283c3b)
**Tracking:** [slot max check-ins](https://www.notion.so/slot-max-check-ins-3364b58e32c3804a8567c07f932fbf93)
**Tag:** `#SlotCapacity`

---

## Context

Today, after a check-in inside a reminder slot's window, the slot stays "current" and continues to nudge — even when the user wouldn't realistically do the activity again so soon (e.g. a 5–8pm workout slot with goal "3× per week" should disappear after one check-in, not nudge again).

PRD chose **per-slot capacity** over a global "cool-off / gap" rule because:

- It extends an existing primitive (`Slot`) instead of adding a new global concept.
- It inherits psych-day boundaries from the existing slot resolution logic, sidestepping the rolling-vs-calendar-day pitfall.
- The "1 workout per day" case naturally collapses to a whole-day slot with `max=1`.

Cross-slot capacity (Path 2) is deferred. The data model in this plan is chosen so that adding a `SlotCapacityGroup` entity later is additive — existing per-slot capacity continues to work without migration.

---

## Architecture Summary

A new optional field `maxCheckIns: Int? = nil` is added to `Slot`. `nil` means unlimited (preserves today's behavior). A slot occurrence is **saturated** when the count of check-ins whose `createdAt` falls inside the resolved occurrence window is ≥ `maxCheckIns`. Saturated occurrences are filtered out of `Commitment.stageStatus` exactly the same way snoozed occurrences are filtered today, so they exit Current/Future and don't contribute to `behindCount` slack.

The cycle target ledger is unchanged: every check-in in the cycle still counts toward `target.count`. `metGoal` continues to be driven by the cycle target only.

The form layer (`SlotDraft`, `SlotWindowRow`) gains an optional capacity stepper that's only relevant when the user wants to cap a slot. Default in UI is "unlimited" with an opt-in to set a max.

---

## Design Decisions

### 1. `maxCheckIns: Int?` directly on `Slot`

**Decision:** Add `var maxCheckIns: Int? = nil` directly on `Slot`. `nil` = unlimited.

**Why not a `SlotCapacity` enum value type?** Pure structural overhead today and doesn't help Path 2 — groups still need a separate entity regardless.

**Why not introduce `SlotCapacityGroup` now?** YAGNI. Every group would have exactly 1 slot. Migrating every existing slot for a feature with one known use case is wasteful.

**Path 2 forward-compat:** when groups are needed, add a `SlotCapacityGroup` entity with its own `maxCheckIns: Int?` and an optional `Slot.capacityGroup` relationship. Saturation logic becomes "if `capacityGroup` exists, sum check-ins across all slots in the group; else use `slot.maxCheckIns`." Existing per-slot caps are unaffected. No data migration required because both fields coexist.

### 2. "Inside the window" = `createdAt` within the resolved occurrence's `[start, end)`

**Decision:** A check-in counts toward a slot occurrence's capacity iff `occurrence.start <= checkIn.createdAt < occurrence.end`. End is exclusive to avoid double-counting at slot boundaries; start is inclusive so a check-in at the exact start time counts.

**Why not psych-day membership?** Out-of-window check-ins (e.g. noon backfill while slot is 5–8pm) explicitly do NOT saturate the slot. PRD: backfilling out-of-slot is user-driven and snooze remains the tool for "I'm not going to do this today."

### 3. Saturation gate matches the snooze gate exactly

**Decision:** In `Commitment.stageStatus`, treat a saturated occurrence the same way snoozed occurrences are treated today: filter them out of `remainingPairs` so they don't count toward "remaining slots" and don't appear in `nextUpSlots`.

**Why?** Snooze and saturation are semantically equivalent for Stage purposes ("this occurrence is no longer asking for action"). Reusing the gate keeps `behindCount`, Current, Future, catch-up, and metGoal precedence correct without re-deriving them. It also implicitly covers reminder-suppression: `CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask` and the Live Activity / widget pipelines all consume `stageStatus`/`CommitmentAndSlot.*WithBehind`, so saturated occurrences are excluded from notification scheduling for free.

**Risk: saturation-driven `catchUp` flip.** If a user has 3 slots all saturated but cycle target = 5, the commitment falls into `catchUp` (mirrors today's behavior when slots are snoozed and target is unmet). This is correct — they did the work but the cycle isn't done; the catch-up presence reflects that real gap.

### 4. Capacity = 0 disallowed; capacity > target allowed

**Decision:** The form treats `1` as the minimum settable value. To "turn the slot off," users use the existing snooze / disable-reminders mechanisms. `max > target.count` is allowed but inert (cycle target hits first).

### 5. UI: opt-in cap with stepper, default off

**Decision:** Each `SlotWindowRow` gains a "Limit" toggle (off by default). When on, a numeric stepper bound to `maxCheckIns` (default 1, min 1) appears. When off, `maxCheckIns = nil`.

**Why not always-visible stepper?** Keeps the row compact for the common case (no cap). Mirrors how the existing whole-day toggle works.

---

## Major Model Changes


| Entity                                                               | Change                                                                                             |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `Shared/Models/Slot.swift`                                           | Add `var maxCheckIns: Int? = nil`                                                                  |
| `Shared/Models/Commitment.swift`                                     | In `stageStatus`, filter saturated occurrences out of `remainingPairs` (mirrors snooze filter)     |
| `Wilgo/Features/Commitments/SlotView.swift`                          | `SlotDraft.maxCheckIns: Int?`, "Limit" toggle + stepper in `SlotWindowRow`                         |
| `Wilgo/Features/Commitments/AddCommitView.swift`                     | Persist `window.maxCheckIns` when constructing `Slot`                                              |
| `Wilgo/Features/Commitments/EditCommitmentView.swift`                | Persist `window.maxCheckIns` when constructing `Slot`; hydrate `SlotDraft` from `slot.maxCheckIns` |
| `WilgoTests/Slot/SlotCapacityTests.swift` (new)                      | Saturation predicate tests on `Slot`                                                               |
| `WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift` (new) | `stageStatus` integration tests for saturation across categories                                   |


No SwiftData schema migration is required — adding an `Optional<Int>` with a default of `nil` is a non-breaking schema change in SwiftData. No `Schema([...])` lists need updating.

---

## Commit Plan

### Phase 1 — Model

#### Commit 1 — feat: add `maxCheckIns` to Slot + saturation predicate `#SlotCapacity`

**Goal:** Add the storage field and a pure predicate that asks "is this slot occurrence saturated by these check-ins, at this time?". No behavior change at this commit — Stage still ignores capacity.

**Modify:** `Shared/Models/Slot.swift`

Add inside the `@Model final class Slot` body, immediately after `var end: Date`:

```swift
/// Optional cap on how many check-ins inside one resolved occurrence's window
/// can satisfy this slot. `nil` = unlimited (default).
///
/// Capacity is per-occurrence: a recurring slot's Monday occurrence and
/// Tuesday occurrence each have their own cap.
///
/// Forward-compat: a future `SlotCapacityGroup` entity (Path 2) will hold its
/// own `maxCheckIns` for cross-slot capacity. The two fields will coexist;
/// when a slot has a group, the group's cap supersedes this one.
var maxCheckIns: Int? = nil
```

Add a new extension at the bottom of `Shared/Models/Slot.swift`:

```swift
// MARK: - Capacity

extension Slot {
    /// Returns true if this slot's occurrence on the psych-day of `time`
    /// has been saturated by check-ins whose `createdAt` falls in
    /// `[occurrence.start, occurrence.end)`.
    ///
    /// Returns false if:
    /// - `maxCheckIns` is nil (unlimited), or
    /// - `time` is outside this slot's scheduled window (no occurrence to saturate).
    func isSaturated(
        at time: Date,
        checkIns: [CheckIn],
        calendar: Calendar = Time.calendar
    ) -> Bool {
        guard let cap = maxCheckIns, cap > 0 else { return false }
        guard self.isScheduled(on: time, calendar: calendar) else { return false }

        // Resolve the occurrence anchored on `time`'s psych-day in order to
        // get concrete [start, end) datetimes. Use the same anchorDate logic
        // implicit in resolveOccurrence by walking from the calendar day of `time`.
        let psychDay = calendar.startOfDay(for: time)
        guard let occurrence = self.resolveOccurrence(on: psychDay, calendar: calendar) else {
            return false
        }
        return Self.countCheckInsInWindow(
            checkIns: checkIns,
            start: occurrence.start,
            end: occurrence.end
        ) >= cap
    }

    /// Pure helper: how many check-ins fall in `[start, end)` by `createdAt`.
    static func countCheckInsInWindow(
        checkIns: [CheckIn],
        start: Date,
        end: Date
    ) -> Int {
        checkIns.reduce(0) { acc, checkIn in
            (checkIn.createdAt >= start && checkIn.createdAt < end) ? acc + 1 : acc
        }
    }
}
```

**Create:** `WilgoTests/Slot/SlotCapacityTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot capacity — isSaturated", .serialized)
final class SlotCapacityTests {

    // MARK: - Helpers

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitmentAndSlot(
        cap: Int?,
        start: Int = 9, end: Int = 11,
        in ctx: ModelContext
    ) -> (Commitment, Slot) {
        let slot = Slot(start: tod(hour: start), end: tod(hour: end))
        slot.maxCheckIns = cap
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 5)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return (commitment, slot)
    }

    // MARK: - nil cap → never saturated

    @Test("maxCheckIns nil → not saturated regardless of check-ins")
    @MainActor func nilCap_neverSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: nil, in: ctx)

        let now = date(2026, 3, 5, 10)
        let ci = CheckIn(commitment: commitment, createdAt: now)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: now, checkIns: [ci]) == false)
    }

    // MARK: - cap reached by in-window check-ins

    @Test("cap=1, one in-window check-in → saturated")
    @MainActor func capOne_oneInWindow_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let now = date(2026, 3, 5, 10)  // inside 9-11 window
        let ci = CheckIn(commitment: commitment, createdAt: now)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: now, checkIns: [ci]) == true)
    }

    @Test("cap=2, two in-window check-ins → saturated")
    @MainActor func capTwo_twoInWindow_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 2, in: ctx)

        let t1 = date(2026, 3, 5, 9, 30)
        let t2 = date(2026, 3, 5, 10, 30)
        let ci1 = CheckIn(commitment: commitment, createdAt: t1)
        let ci2 = CheckIn(commitment: commitment, createdAt: t2)
        ctx.insert(ci1); ctx.insert(ci2)

        #expect(slot.isSaturated(at: t2, checkIns: [ci1, ci2]) == true)
    }

    // MARK: - out-of-window check-ins do NOT saturate

    @Test("cap=1, only out-of-window check-in → not saturated")
    @MainActor func capOne_outOfWindow_notSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let outside = date(2026, 3, 5, 7)  // before 9am window
        let ci = CheckIn(commitment: commitment, createdAt: outside)
        ctx.insert(ci)

        let now = date(2026, 3, 5, 10)
        #expect(slot.isSaturated(at: now, checkIns: [ci]) == false)
    }

    // MARK: - end is exclusive

    @Test("cap=1, check-in exactly at end → not saturated")
    @MainActor func capOne_atEndBoundary_notSaturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let atEnd = date(2026, 3, 5, 11)  // exactly window end
        let ci = CheckIn(commitment: commitment, createdAt: atEnd)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: atEnd, checkIns: [ci]) == false)
    }

    @Test("cap=1, check-in exactly at start → saturated")
    @MainActor func capOne_atStartBoundary_saturated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let atStart = date(2026, 3, 5, 9)
        let ci = CheckIn(commitment: commitment, createdAt: atStart)
        ctx.insert(ci)

        #expect(slot.isSaturated(at: atStart, checkIns: [ci]) == true)
    }

    // MARK: - capacity is per-occurrence (different days are independent)

    @Test("cap=1, yesterday saturated does NOT saturate today")
    @MainActor func capOne_yesterdayDoesNotSaturateToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (commitment, slot) = makeCommitmentAndSlot(cap: 1, in: ctx)

        let yesterdayCheckIn = date(2026, 3, 4, 10)
        let ci = CheckIn(commitment: commitment, createdAt: yesterdayCheckIn)
        ctx.insert(ci)

        let today = date(2026, 3, 5, 10)
        #expect(slot.isSaturated(at: today, checkIns: [ci]) == false)
    }

    // MARK: - whole-day slot

    @Test("whole-day slot, cap=1, any same-day check-in → saturated")
    @MainActor func wholeDay_capOne_anyCheckInSaturates() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Whole-day sentinel: start == end
        let slot = Slot(start: tod(hour: 0), end: tod(hour: 0))
        slot.maxCheckIns = 1
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 1)
        )
        ctx.insert(commitment); ctx.insert(slot)

        let nowMorning = date(2026, 3, 5, 7)
        let ciMorning = CheckIn(commitment: commitment, createdAt: nowMorning)
        ctx.insert(ciMorning)

        let nowEvening = date(2026, 3, 5, 22)
        #expect(slot.isSaturated(at: nowEvening, checkIns: [ciMorning]) == true)
    }
}
```

**Run only this test file** (per CLAUDE.md "first only run the test relative to your change"):

```bash
./test-with-cleanup.sh -only-testing WilgoTests/SlotCapacityTests
```

Expected: all 8 tests pass.

**Commit:**

```bash
git add Shared/Models/Slot.swift WilgoTests/Slot/SlotCapacityTests.swift
git commit -m "$(cat <<'EOF'
feat: add maxCheckIns + isSaturated predicate to Slot #SlotCapacity

tracking: https://www.notion.so/slot-max-check-ins-3364b58e32c3804a8567c07f932fbf93
EOF
)"
```

---

### Phase 2 — Stage integration

#### Commit 2 — feat: filter saturated occurrences from stageStatus `#SlotCapacity`

**Goal:** Make `Commitment.stageStatus` treat a saturated occurrence the same as a snoozed occurrence — drop it from `remainingPairs`. This is the core behavior change.

**Modify:** `Shared/Models/Commitment.swift`

Replace the snooze-filter block at lines 204-211 with:

```swift
// Remaining slot occurrences in the cycle that have not yet ended.
// Filter out occurrences that are currently active and either snoozed or saturated.
// Only active occurrences (start <= now) can be filtered — future ones are always kept.
var remainingPairs: [(occurrence: Slot, original: Slot)]
if let firstNotEndedIndex = resolvedPairs.firstIndex(where: { $0.occurrence.end >= now }) {
    remainingPairs = resolvedPairs[firstNotEndedIndex...].filter { pair in
        if pair.occurrence.start > now { return true }
        if pair.original.isSnoozed(at: now) { return false }
        if pair.original.isSaturated(at: now, checkIns: checkInsInCycle) { return false }
        return true
    }
} else {
    remainingPairs = []
}
```

The `checkInsInCycle` array is already in scope at this point (computed at line 143).

**Create:** `WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Commitment.stageStatus — slot capacity", .serialized)
final class CommitmentSlotCapacityStageTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(
        slotsWithCap: [(start: Int, end: Int, cap: Int?)],
        targetCount: Int,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(2026, 1, 1)
        let slots = slotsWithCap.map { def -> Slot in
            let s = Slot(start: tod(hour: def.start), end: tod(hour: def.end))
            s.maxCheckIns = def.cap
            return s
        }
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: QuantifiedCycle(count: targetCount)
        )
        ctx.insert(commitment)
        slots.forEach { ctx.insert($0) }
        return commitment
    }

    // MARK: - Saturated current slot exits .current

    @Test("active slot with cap=1, one in-window check-in → drops out of .current")
    @MainActor func saturatedSoleSlot_dropsToCatchUpWhenTargetUnmet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Single slot 9-11, cap=1, target=2 (so saturating one slot doesn't meet the goal)
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1)],
            targetCount: 2,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let ci = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(ci)
        commitment.checkIns = [ci]

        let now = date(2026, 3, 5, 10, 30)
        let status = commitment.stageStatus(now: now)
        // Saturated → no remaining slots → catchUp (target not yet met)
        #expect(status.category == .catchUp)
        #expect(status.nextUpSlots.isEmpty)
    }

    @Test("two slots, first cap=1 saturated → status is .future on second")
    @MainActor func saturatedFirstSlot_secondSlotIsFuture() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 9-11 cap=1 (will be saturated), 15-17 cap=nil
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1), (15, 17, nil)],
            targetCount: 2,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let ci = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(ci)
        commitment.checkIns = [ci]

        let now = date(2026, 3, 5, 10, 30)  // still inside the saturated 9-11 window
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .future)
        #expect(status.nextUpSlots.allSatisfy { $0.start > now })
    }

    // MARK: - cap reached but target met → .metGoal precedence

    @Test("cap=1 saturated AND target met → .metGoal (precedence over capacity filter)")
    @MainActor func saturatedAndTargetMet_isMetGoal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, 1)],
            targetCount: 1,
            in: ctx
        )

        let checkInTime = date(2026, 3, 5, 10)
        let ci = CheckIn(commitment: commitment, createdAt: checkInTime)
        ctx.insert(ci)
        commitment.checkIns = [ci]

        let now = date(2026, 3, 5, 10, 30)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .metGoal)
    }

    // MARK: - out-of-window check-in does NOT saturate (regression of PRD invariant)

    @Test("cap=1 with only out-of-window check-in → slot remains .current")
    @MainActor func outOfWindowCheckIn_doesNotSaturate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(17, 20, 1)],
            targetCount: 2,
            in: ctx
        )

        // Backfill at noon — outside 5-8pm window
        let backfillTime = date(2026, 3, 5, 12)
        let ci = CheckIn(commitment: commitment, createdAt: backfillTime, source: .backfill)
        ctx.insert(ci)
        commitment.checkIns = [ci]

        let now = date(2026, 3, 5, 18)  // inside 5-8pm
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .current)
    }

    // MARK: - nil cap is unchanged behavior

    @Test("cap=nil with two in-window check-ins → still .current (no regression)")
    @MainActor func nilCap_inWindowCheckIns_stillCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let commitment = makeCommitment(
            slotsWithCap: [(9, 11, nil)],
            targetCount: 5,
            in: ctx
        )

        let ci1 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 30))
        let ci2 = CheckIn(commitment: commitment, createdAt: date(2026, 3, 5, 9, 45))
        ctx.insert(ci1); ctx.insert(ci2)
        commitment.checkIns = [ci1, ci2]

        let now = date(2026, 3, 5, 10)
        let status = commitment.stageStatus(now: now)
        #expect(status.category == .current)
    }

    // MARK: - whole-day slot with cap=1

    @Test("whole-day slot cap=1, morning check-in → not .current at evening")
    @MainActor func wholeDayCap1_morningCheckIn_notCurrentAtEvening() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Whole-day slot: start == end == midnight
        let slot = Slot(start: tod(hour: 0), end: tod(hour: 0))
        slot.maxCheckIns = 1
        let commitment = Commitment(
            title: "T",
            cycle: Cycle(kind: .daily, referencePsychDay: date(2026, 1, 1)),
            slots: [slot],
            target: QuantifiedCycle(count: 1)
        )
        ctx.insert(commitment); ctx.insert(slot)

        let morning = date(2026, 3, 5, 7)
        let ci = CheckIn(commitment: commitment, createdAt: morning)
        ctx.insert(ci)
        commitment.checkIns = [ci]

        let evening = date(2026, 3, 5, 22)
        let status = commitment.stageStatus(now: evening)
        // target=1 was met → metGoal short-circuits
        #expect(status.category == .metGoal)
    }
}
```

**Run only the new + adjacent tests** (snooze tests share the same code path; we want to confirm we didn't break them):

```bash
./test-with-cleanup.sh -only-testing WilgoTests/CommitmentSlotCapacityStageTests \
  -only-testing WilgoTests/CommitmentStageSnoozeTests
```

Expected: all `CommitmentSlotCapacityStageTests` pass; `CommitmentStageSnoozeTests` pass except the pre-existing failing test `stageStatus_snoozeDoesNotAffectFutureOccurrence` (per CLAUDE.md, ignore that one).

**Commit:**

```bash
git add Shared/Models/Commitment.swift WilgoTests/Commitment/CommitmentSlotCapacityStageTests.swift
git commit -m "$(cat <<'EOF'
feat: filter saturated slot occurrences from stageStatus #SlotCapacity

tracking: https://www.notion.so/slot-max-check-ins-3364b58e32c3804a8567c07f932fbf93
EOF
)"
```

---

### Phase 3 — Form layer

#### Commit 3 — feat: SlotDraft.maxCheckIns + persist in Add/Edit `#SlotCapacity`

**Goal:** Wire the new field through the form value type and the two persistence sites. UI is added in Commit 4. After this commit the model is end-to-end persistable, just not user-facing yet.

**Modify:** `Wilgo/Features/Commitments/SlotView.swift`

In `SlotDraft`, add the new field after `isWholeDay`:

```swift
/// Optional cap on check-ins inside one occurrence's window. nil = unlimited.
var maxCheckIns: Int? = nil
```

**Modify:** `Wilgo/Features/Commitments/AddCommitView.swift`

Replace the slot construction in `persistCommitment` (line 81-85) with:

```swift
let slots: [Slot] =
    effectiveRemindersEnabled
    ? slotWindows.map { window in
        let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
        slot.maxCheckIns = window.maxCheckIns
        modelContext.insert(slot)
        return slot
    } : []
```

**Modify:** `Wilgo/Features/Commitments/EditCommitmentView.swift`

Replace the `SlotDraft` hydration in `init` (line 33-37) with:

```swift
_slotWindows = State(
    initialValue: commitment.slots.sorted().map {
        SlotDraft(
            start: $0.start,
            end: $0.end,
            recurrence: $0.recurrence,
            isWholeDay: $0.isWholeDay,
            maxCheckIns: $0.maxCheckIns
        )
    }
)
```

Replace the slot construction in `saveChanges` (lines 159-165) with:

```swift
for old in commitment.slots { modelContext.delete(old) }
let newSlots: [Slot] = slotWindows.map { window in
    let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
    slot.maxCheckIns = window.maxCheckIns
    modelContext.insert(slot)
    return slot
}
commitment.slots = newSlots.sorted()
```

> **Note:** `SlotDraft` is a struct with default-valued fields, so adding `isWholeDay` and `maxCheckIns` to the call site is purely additive — call sites that didn't pass them are unaffected. Verify by searching for other `SlotDraft(` callers; in this codebase the two above are the only ones.

**Verify hydration:** add a unit test that round-trips a slot with `maxCheckIns` through `SlotDraft` is not necessary here because the Edit/Add views are SwiftUI Views — instead, integration is covered by the round-trip test below.

**Create:** `WilgoTests/Slot/SlotMaxCheckInsRoundTripTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Slot.maxCheckIns — SwiftData round-trip", .serialized)
final class SlotMaxCheckInsRoundTripTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @Test("Slot persists nil maxCheckIns by default")
    @MainActor func defaultIsNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Slot>()).first!
        #expect(fetched.maxCheckIns == nil)
    }

    @Test("Slot round-trips an explicit maxCheckIns")
    @MainActor func roundTripsExplicitValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        slot.maxCheckIns = 1
        ctx.insert(slot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Slot>()).first!
        #expect(fetched.maxCheckIns == 1)
    }
}
```

**Run only:**

```bash
./test-with-cleanup.sh -only-testing WilgoTests/SlotMaxCheckInsRoundTripTests
```

Expected: 2 tests pass.

**Commit:**

```bash
git add Wilgo/Features/Commitments/SlotView.swift \
        Wilgo/Features/Commitments/AddCommitView.swift \
        Wilgo/Features/Commitments/EditCommitmentView.swift \
        WilgoTests/Slot/SlotMaxCheckInsRoundTripTests.swift
git commit -m "$(cat <<'EOF'
feat: persist Slot.maxCheckIns through Add/Edit forms #SlotCapacity

tracking: https://www.notion.so/slot-max-check-ins-3364b58e32c3804a8567c07f932fbf93
EOF
)"
```

---

#### Commit 4 — feat: Limit toggle + stepper in SlotWindowRow `#SlotCapacity`

**Goal:** Surface `maxCheckIns` in the per-slot row UI. Off by default; opt in to set a max.

**Modify:** `Wilgo/Features/Commitments/SlotView.swift`

Inside `SlotWindowRow`'s `body`, in the inner `VStack(alignment: .leading, spacing: 6)` (around line 89), insert this block immediately AFTER the "Repeat" button (around line 165, before the closing `}` of the inner VStack):

```swift
Toggle("Limit check-ins", isOn: limitBinding)
    .font(.footnote)

if window.maxCheckIns != nil {
    HStack(spacing: 8) {
        Text("Max")
            .foregroundStyle(.secondary)
        Stepper(
            value: maxCheckInsStepperBinding,
            in: 1...20
        ) {
            Text("\(window.maxCheckIns ?? 1)")
                .monospacedDigit()
        }
    }
    .font(.footnote)
}
```

Add these two computed bindings inside `SlotWindowRow`, next to `wholeDayBinding`:

```swift
private var limitBinding: Binding<Bool> {
    Binding(
        get: { window.maxCheckIns != nil },
        set: { newValue in
            window.maxCheckIns = newValue ? 1 : nil
        }
    )
}

private var maxCheckInsStepperBinding: Binding<Int> {
    Binding(
        get: { window.maxCheckIns ?? 1 },
        set: { window.maxCheckIns = max(1, $0) }
    )
}
```

**Manual verification on iPhone 17 simulator (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`):**

1. Open the app, create a new commitment with one reminder slot. Verify "Limit check-ins" toggle appears, defaulted off.
2. Toggle "Limit check-ins" on. Verify the "Max" stepper appears at 1.
3. Step up to 3, step back down. Verify the value clamps at 1 (cannot go below).
4. Save. Re-open the commitment via Edit. Verify the toggle is on and the value is 3.
5. Toggle "Limit check-ins" off. Save. Re-open. Verify the toggle is off.
6. With cap=1, set the slot to a window covering "now". Tap check-in once. Verify the slot disappears from the Stage's Current/Future and the commitment moves to either `metGoal` (if target=1) or `catchUp` (if target>1).

**Build to confirm no compiler errors:**

```bash
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'
```

Expected: BUILD SUCCEEDED.

**Commit:**

```bash
git add Wilgo/Features/Commitments/SlotView.swift
git commit -m "$(cat <<'EOF'
feat: Limit check-ins toggle + stepper in SlotWindowRow #SlotCapacity

tracking: https://www.notion.so/slot-max-check-ins-3364b58e32c3804a8567c07f932fbf93
EOF
)"
```

---

### Phase 4 — Full test sweep

#### Commit 5 — test: full suite green check `#SlotCapacity`

**Goal:** Verify no regressions across the full test suite. Per CLAUDE.md, the only pre-existing failure is `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence` — ignore that one.

```bash
./test-with-cleanup.sh
```

Expected: all tests pass except the documented pre-existing failure.

If everything is green, no extra commit is needed for this phase. If new failures appear, fix in this phase before declaring the feature done.

---

## Critical Files


| File                                                  | Role                                              |
| ----------------------------------------------------- | ------------------------------------------------- |
| `Shared/Models/Slot.swift`                            | New `maxCheckIns` field + `isSaturated` predicate |
| `Shared/Models/Commitment.swift`                      | `stageStatus` saturation filter                   |
| `Wilgo/Features/Commitments/SlotView.swift`           | `SlotDraft.maxCheckIns` + UI toggle/stepper       |
| `Wilgo/Features/Commitments/AddCommitView.swift`      | Persist on creation                               |
| `Wilgo/Features/Commitments/EditCommitmentView.swift` | Hydrate + persist on edit                         |


### Dependency Graph

```
Commit 1: Slot field + isSaturated + unit tests
    |
    +-- Commit 2: stageStatus filter + integration tests   [after 1]
    |       |
    |       +-- Commit 5: full test sweep                  [after 2, 4]
    |
    +-- Commit 3: SlotDraft + Add/Edit persistence         [parallel after 1]
    |       |
    |       +-- Commit 4: SlotWindowRow UI                 [after 3]
    |               |
    |               +-- Commit 5                            [after 2, 4]
```

Commits 2 and 3 are independent and can be parallelized after Commit 1. Commit 4 depends on Commit 3. Commit 5 is a final verification gate.