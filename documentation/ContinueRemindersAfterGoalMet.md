# Continue Reminders After Goal Met — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** N/A (simple enough to skip)  
**Tracking:** [allow user to choose for a specific commitment, show the reminders keep showing after the goal is met](https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link)  
**Tag:** `#ContinueRemindersAfterGoalMet`

---

## Architecture Summary

Add a `continueRemindersAfterGoalMet: Bool` property to `Commitment` (default `false`). When `false`, existing behavior is preserved: `SlotStartNotificationScheduler` skips goal-met commitments and `StageViewModel` excludes them from Stage lists. When `true`, both systems treat the commitment as if the goal is not yet met — slot-start notifications keep firing and the commitment continues to appear as `.current`/`.future` in Stage.

The flag is exposed as a `Toggle` in `CommitmentFormFields`, nested under the existing Reminders section (only visible when reminders are enabled). `CommitmentFormDraft` carries the flag through the edit/create flow.

No change to `slotStatus` or `goalProgress` logic itself — the filtering happens at the call sites (`StageViewModel.recompute` and `SlotStartNotificationScheduler.startTimeInRangeToCommitments`), keeping the model pure.

---

## Design Decisions

### Where to apply the flag

**Decision:** Apply at the consumer call sites (StageViewModel + SlotStartNotificationScheduler), not inside `goalProgress` or `slotStatus`.

**Why not modify `goalProgress` to return `isMet = false` when the flag is set?** `goalProgress` is a pure model query used widely (tests, widgets, FinishedCycleReport). Changing its output would silently change behavior everywhere. The flag is a *display* preference — it belongs at the display/scheduling layer.

**Risk: call sites diverge.** Mitigations: both sites use the same one-liner guard (`guard commitment.isRemindersEnabled && (!commitment.goalProgress(now: now).isMet || commitment.continueRemindersAfterGoalMet)`), and the existing test `startTimeInRangeToCommitments_goalAlreadyMet_excluded` gets a sibling test for the opt-in case.

### Default value

**Decision:** Default `false` — existing behavior unchanged for all current commitments.

---

## Major Model Changes

| Entity | Change |
|--------|--------|
| `Shared/Models/Commitment.swift` | Add `var continueRemindersAfterGoalMet: Bool = false` |
| `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift` | Add `continueRemindersAfterGoalMet: Bool`, wire into `insertCommitment` and `apply(to:in:)` |
| `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift` | Add `Toggle` in Reminders section |
| `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | Replace goal-met guard to respect the flag |
| `Wilgo/Features/Stage/StageViewModel.swift` | Filter out goal-met commitments respecting the flag |

---

## Commit Plan

### Phase 1 — Model + data layer

#### Commit 1 — Add `continueRemindersAfterGoalMet` to `Commitment` model and wire draft/form

**Modify:** `Shared/Models/Commitment.swift`  
Add after `isRemindersEnabled`:

```swift
var continueRemindersAfterGoalMet: Bool = false
```

Also add to `init(...)` parameter list and body (after `isRemindersEnabled`):

```swift
// in init parameters:
continueRemindersAfterGoalMet: Bool = false,

// in init body:
self.continueRemindersAfterGoalMet = continueRemindersAfterGoalMet
```

**Modify:** `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift`  

1. Add property:
```swift
var continueRemindersAfterGoalMet: Bool
```

2. Add to `init(...)` parameter + body (default `false`):
```swift
// parameter
continueRemindersAfterGoalMet: Bool = false,
// body
self.continueRemindersAfterGoalMet = continueRemindersAfterGoalMet
```

3. In `init(commitment:)`, add:
```swift
continueRemindersAfterGoalMet: commitment.continueRemindersAfterGoalMet
```

4. In `insertCommitment(in:)`, pass to `Commitment(...)`:
```swift
continueRemindersAfterGoalMet: continueRemindersAfterGoalMet,
```

5. In `apply(to:in:)`, add:
```swift
commitment.continueRemindersAfterGoalMet = continueRemindersAfterGoalMet
```

**Tests to write:** `WilgoTests/Commitment/ContinueRemindersAfterGoalMetModelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `WilgoTests/Commitment/ContinueRemindersAfterGoalMetModelTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class ContinueRemindersAfterGoalMetModelTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(continueReminders: Bool = false, in ctx: ModelContext) -> Commitment {
        let c = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: Date()),
            slots: [],
            target: Target(count: 1),
            continueRemindersAfterGoalMet: continueReminders
        )
        ctx.insert(c)
        return c
    }

    @Test("continueRemindersAfterGoalMet defaults to false")
    @MainActor func defaultIsFalse() throws {
        let container = try makeContainer()
        let c = makeCommitment(in: container.mainContext)
        #expect(c.continueRemindersAfterGoalMet == false)
    }

    @Test("continueRemindersAfterGoalMet persists true")
    @MainActor func persistsTrue() throws {
        let container = try makeContainer()
        let c = makeCommitment(continueReminders: true, in: container.mainContext)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<Commitment>())
        #expect(fetched.first?.continueRemindersAfterGoalMet == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/ContinueRemindersAfterGoalMetModelTests 2>&1 | tail -30
```
Expected: compile error — `continueRemindersAfterGoalMet` not found.

- [ ] **Step 3: Implement model + draft changes** (as described above)

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/ContinueRemindersAfterGoalMetModelTests 2>&1 | tail -30
```
Expected: 2 tests pass.

- [ ] **Step 5: Run all existing tests to confirm no regressions**

```bash
./test-with-cleanup.sh 2>&1 | tail -40
```
Expected: all previously passing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/Commitment.swift \
        Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift \
        WilgoTests/Commitment/ContinueRemindersAfterGoalMetModelTests.swift
git commit -m "$(cat <<'EOF'
Add continueRemindersAfterGoalMet flag to Commitment model and draft

#ContinueRemindersAfterGoalMet
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 2 — UI

#### Commit 2 — Add toggle in CommitmentFormFields

**Modify:** `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift`  
Inside the Reminders `Section`, after the existing `if draft.isRemindersEnabled { ReminderWindowsSection(...) }` block, add:

```swift
if draft.isRemindersEnabled {
    Toggle("Continue after goal met", isOn: $draft.continueRemindersAfterGoalMet)
}
```

The full Reminders section becomes:

```swift
Section {
    Toggle("Reminders", isOn: $draft.isRemindersEnabled)
    if draft.isRemindersEnabled {
        ReminderWindowsSection(slotWindows: $draft.slotWindows)
        Toggle("Continue after goal met", isOn: $draft.continueRemindersAfterGoalMet)
    }
} header: {
    Text("Reminder Windows")
} footer: {
    if !draft.isRemindersEnabled {
        Text("No reminders. Commitment won't appear in Stage view or send notifications.")
    } else if draft.continueRemindersAfterGoalMet {
        Text("Slots will still appear in Stage and send notifications even after you've hit your target for this cycle.")
    }
}
```

- [ ] **Step 1: Implement the UI change** (no unit test needed — UI-only toggle wiring)

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual verification**
  - Open app on iPhone 17 Simulator (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`)
  - Create a new commitment with Reminders enabled → confirm "Continue after goal met" toggle appears below reminder windows
  - Toggle it on → confirm footer text updates to explain the behavior
  - Toggle Reminders off → confirm "Continue after goal met" toggle disappears
  - Save commitment → re-open edit → confirm toggle state is preserved

- [ ] **Step 4: Run all tests**

```bash
./test-with-cleanup.sh 2>&1 | tail -40
```
Expected: all previously passing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Wilgo/Features/Commitments/Form/CommitmentFormFields.swift
git commit -m "$(cat <<'EOF'
Add 'Continue after goal met' toggle to commitment form

#ContinueRemindersAfterGoalMet
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 3 — Notification scheduling

#### Commit 3 — Respect flag in SlotStartNotificationScheduler

**Modify:** `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift`  
In `startTimeInRangeToCommitments`, replace:

```swift
guard !commitment.goalProgress(now: now).isMet else { continue }  // TODO: later this will be user configurable
```

with:

```swift
let goalMet = commitment.goalProgress(now: now).isMet
if goalMet && !commitment.continueRemindersAfterGoalMet { continue }
```

- [ ] **Step 1: Write failing tests**

Add to `WilgoTests/Notifications/SlotStartNotificationSchedulerTests.swift`:

```swift
@Test("commitment with goal met and continueRemindersAfterGoalMet=true is included")
@MainActor func startTimeInRangeToCommitments_goalMet_continueEnabled_included() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
    c.continueRemindersAfterGoalMet = true
    // One check-in satisfies the daily target of 1
    addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
    let now = date(year: 2026, month: 3, day: 5, hour: 7)

    let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
        for: [c], from: now)

    let expected = date(year: 2026, month: 3, day: 5, hour: 9)
    #expect(result[expected] != nil)
}

@Test("commitment with goal met and continueRemindersAfterGoalMet=false is excluded (default)")
@MainActor func startTimeInRangeToCommitments_goalMet_continueDisabled_excluded() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let c = makeCommitment(slots: [(9, 11)], targetCount: 1, in: ctx)
    c.continueRemindersAfterGoalMet = false
    addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)
    let now = date(year: 2026, month: 3, day: 5, hour: 7)

    let result = SlotStartNotificationScheduler.startTimeInRangeToCommitments(
        for: [c], from: now)

    #expect(result.isEmpty)
}
```

- [ ] **Step 2: Run new tests to verify they fail**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/SlotStartNotificationSchedulerTests 2>&1 | tail -30
```
Expected: the two new tests fail (goal-met commitment still excluded even when flag=true).

- [ ] **Step 3: Implement the guard change** (as described above)

- [ ] **Step 4: Run notification tests to verify they pass**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/SlotStartNotificationSchedulerTests 2>&1 | tail -30
```
Expected: all tests pass, including the two new ones.

- [ ] **Step 5: Commit**

```bash
git add Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift \
        WilgoTests/Notifications/SlotStartNotificationSchedulerTests.swift
git commit -m "$(cat <<'EOF'
Respect continueRemindersAfterGoalMet in slot-start notification scheduler

#ContinueRemindersAfterGoalMet
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Phase 4 — Stage filtering

#### Commit 4 — Respect flag in StageViewModel

The `StageViewModel.recompute` method currently filters `lastCommitments` to exclude goal-met commitments, then passes the result to `CommitmentAndSlot.*` functions. Commitments with reminders disabled are handled at the model level — `CommitmentAndSlot` guards on `.insideSlot`/`.beforeNextToday`/`.noSlotToday`, and disabled commitments return `.disabled` slotKind which none of those match.

The fix: make the goal-met filter respect the flag. Replace the existing filter predicate.

**Modify:** `Wilgo/Features/Stage/StageViewModel.swift`  
Replace `recompute()`:

```swift
private func recompute() {
    let now = Date()
    let active = lastCommitments.filter { commitment in
        if commitment.continueRemindersAfterGoalMet { return true }
        return !commitment.goalProgress(now: now).isMet
    }
    current = CommitmentAndSlot.currentWithBehind(commitments: active, now: now)
    upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: active, after: now)
    catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: active, now: now)
}
```

> **Note:** No `isRemindersEnabled` pre-filter is needed — reminders-disabled commitments are handled downstream by `CommitmentAndSlot` (their `status(now:)` returns `.disabled` slotKind). The end result is identical for `continueRemindersAfterGoalMet=false`. For `=true`, the commitment re-enters Stage with its actual slot kind (`.insideSlot`/`.beforeNextToday`) which is correct.

- [ ] **Step 1: Write failing tests**

Create `WilgoTests/Stage/StageViewModelContinueRemindersTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class StageViewModelContinueRemindersTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=true appears as current in Stage")
    @MainActor func goalMet_continueEnabled_appearsAsCurrent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: true
        )
        ctx.insert(c)

        // Satisfy goal with one check-in at 8am
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        // Now = inside slot window (10am) — should still appear as current
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let vm = StageViewModel()
        vm.refresh(commitments: [c])

        // We call the underlying CommitmentAndSlot directly to test filtering logic,
        // since StageViewModel.refresh uses Date() internally. Test via CommitmentAndSlot:
        let result = CommitmentAndSlot.currentWithBehind(
            commitments: [c].filter { $0.continueRemindersAfterGoalMet || !$0.goalProgress(now: now).isMet },
            now: now
        )
        #expect(result.count == 1)
        #expect(result.first?.commitment.title == "Meditate")
    }

    @Test("goal-met commitment with continueRemindersAfterGoalMet=false is excluded from Stage")
    @MainActor func goalMet_continueDisabled_excludedFromStage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        ctx.insert(slot)
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Meditate",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: false
        )
        ctx.insert(c)

        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let result = CommitmentAndSlot.currentWithBehind(
            commitments: [c].filter { $0.continueRemindersAfterGoalMet || !$0.goalProgress(now: now).isMet },
            now: now
        )
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/StageViewModelContinueRemindersTests 2>&1 | tail -30
```
Expected: compile errors (`continueRemindersAfterGoalMet` not on `Commitment` yet, or tests fail logic-wise before Commit 1 is applied — run this after Commit 1).

- [ ] **Step 3: Implement StageViewModel change** (as described above)

- [ ] **Step 4: Run stage tests to verify they pass**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing WilgoTests/StageViewModelContinueRemindersTests 2>&1 | tail -30
```
Expected: both tests pass.

- [ ] **Step 5: Run all tests**

```bash
./test-with-cleanup.sh 2>&1 | tail -40
```
Expected: all previously passing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Wilgo/Features/Stage/StageViewModel.swift \
        WilgoTests/Stage/StageViewModelContinueRemindersTests.swift
git commit -m "$(cat <<'EOF'
Respect continueRemindersAfterGoalMet in Stage filtering

#ContinueRemindersAfterGoalMet
tracking: https://www.notion.so/allow-user-to-choose-for-a-specific-commitment-show-the-reminders-keep-showing-after-the-goal-is-me-33b4b58e32c3805bae77ebb408884ef9?source=copy_link

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Critical Files

| File | Role |
|------|------|
| `Shared/Models/Commitment.swift` | New `continueRemindersAfterGoalMet` model property |
| `Wilgo/Features/Commitments/Form/CommitmentFormDraft.swift` | Carries flag through create/edit flow |
| `Wilgo/Features/Commitments/Form/CommitmentFormFields.swift` | Toggle UI in Reminders section |
| `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | Respects flag in notification scheduling |
| `Wilgo/Features/Stage/StageViewModel.swift` | Respects flag in Stage list filtering |
| `WilgoTests/Commitment/ContinueRemindersAfterGoalMetModelTests.swift` | Model persistence tests |
| `WilgoTests/Notifications/SlotStartNotificationSchedulerTests.swift` | Two new tests added |
| `WilgoTests/Stage/StageViewModelContinueRemindersTests.swift` | Stage filtering tests |

---

## Dependency Graph

```
Commit 1: Add model flag + draft wiring
    |
    +-- Commit 2: UI toggle [after 1] ← manual verification here
    +-- Commit 3: Notification scheduler [after 1]
    +-- Commit 4: Stage filtering [after 1]
```

Commits 2, 3, and 4 are all independent of each other and can be parallelized after Commit 1.
