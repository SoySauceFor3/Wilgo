# Commitment Part Disable — Implementation Plan

**PRD:** [Disable parts in Commitments](https://www.notion.so/Disable-parts-in-Commitments-3424b58e32c38047a17eef44d4e835bc)
**Notion task link (for commit messages):** [tracking](https://www.notion.so/disable-able-parts-in-Commitments-3434b58e32c380b5a1bedf6343b16f56)
**Tag:** `#CommitmentPartDisable`

---

## Context

Users want to track a commitment without the full pressure of goals, punishment, or notifications. For example: "I still want to draw on weekends but don't want a daily target or punishment right now."

Three parts of a commitment can be independently disabled:

- **Reminders** (`isRemindersEnabled`) — suppresses slot notifications, Live Activity, Stage/Focus view presence
- **Punishment** (`isPunishmentEnabled`) — suppresses punishment enforcement; PT is still consumed on skips
- **Target** (`Target.isEnabled`) — suppresses cycle goal, cycle end evaluation, and `.metGoal` logic; punishment section is hidden when target is off

Values are **always preserved** when disabled — re-enabling restores them without re-entry.

A temporary "pause with end date" feature was explored but deferred — the permanent toggle covers the immediate need.

---

## Architecture Summary

`Cycle` is moved out of `QuantifiedCycle` (Target) to a top-level field on `Commitment`. This is a prerequisite because cycle drives reporting regardless of whether a goal is set.

Three boolean fields are then added one at a time — each with full-stack coverage (model → business logic → UI) before moving to the next. `isRemindersEnabled` and `isPunishmentEnabled` are flat fields on `Commitment`. `Target.isEnabled` lives inside `QuantifiedCycle` so the count value is preserved alongside its enabled state.

When `Target.isEnabled` is false, `stageStatus` bypasses all goal math and delegates to a private `targetDisabledStatus` helper, which returns `.current`, `.future`, or `.others` (reusing existing categories) with `behindCount` always `0`. The Stage view checks `commitment.target.isEnabled` before rendering goal counters or behind badges.

---

## Design Decisions

### Cycle moved to top-level `Commitment`

**Decision:** `Commitment.cycle: Cycle` replaces `QuantifiedCycle.cycle`. `QuantifiedCycle` retains only `count` (and later `isEnabled`).

**Why not leave cycle in Target?** Cycle drives reporting (FinishedCycleReport, check-in grouping, stage categorization) regardless of whether a goal is active. Keeping it inside Target would require special-casing "target disabled but cycle still exists" everywhere.

### Flat booleans on `Commitment`, not a grouped `CommitmentSettings` struct

**Decision:** `isRemindersEnabled` and `isPunishmentEnabled` are direct `@Attribute` fields on `Commitment`, not wrapped in an embedded struct.

**Why not group them?** The grouped struct approach adds indirection with no current benefit — there's no shared logic between the two flags. Can be refactored into a struct later if a third flag needs grouping.

### `isRemindersEnabled` is a flat field, not grouped with `slots` into a struct

**Decision:** `isRemindersEnabled` is a direct `@Attribute` field on `Commitment`, not wrapped in a struct alongside `slots`.

**Why not group them?** `slots` is a SwiftData `@Relationship` and must live directly on the `@Model` class — SwiftData does not support `@Relationship` inside a plain `struct`. The struct would have to either become a nested `@Model` (overkill, adds a full persistence entity) or store slot UUIDs (which violates the repo rule of preferring direct references over UUIDs for relationships).

### `Target.isEnabled` lives inside `QuantifiedCycle`

**Decision:** `QuantifiedCycle` gains `var isEnabled: Bool = true` so that `count` and `isEnabled` travel together.

**Why not a flat field on `Commitment`?** The count value must survive toggling off and back on. Keeping it adjacent to count inside the same struct makes the preservation contract obvious.

### `isRemindersEnabled` filter lives at the call site, not inside `CommitmentAndSlot` helpers

**Decision:** `StageViewModel.recompute()` (and `CatchUpReminder`) filter commitments by `isRemindersEnabled` before passing the slice to `currentWithBehind`, `upcomingWithBehind`, and `catchUpWithBehind`. The helpers themselves are not modified.

**Why not filter inside the helpers?**

- The helpers' contract is "classify what you're given" — embedding a reminder-business-rule inside them violates single responsibility.
- Filtering at the call site is explicit and auditable; filtering inside helpers risks silent double-filtering if other callers also pre-filter.
- Keeping helpers pure makes them easier to test and reuse in non-Stage contexts (e.g. widgets, notifications) where the caller may legitimately want a different filter.

**Concrete pattern (Commit 2):**

```swift
// StageViewModel.recompute()
let remindersOn = lastCommitments.filter { $0.isRemindersEnabled }
current  = CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now)
upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: remindersOn, after: now)
catchUp  = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn, now: now)
```

Same pattern in `CatchUpReminder` before its `catchUpWithBehind` call.

### Values are always preserved when a part is disabled

**Decision:** Disabling a part never destroys the underlying data. Re-enabling restores it without re-entry.

**How this applies to each part:**

- `**isRemindersEnabled` (slots):** Slots are only written to DB when `effectiveRemindersEnabled = isRemindersEnabled && !slotWindows.isEmpty` is true. When disabled, existing DB slots are left untouched. In the edit form, `slotWindows` state is kept populated even when the toggle is off — the UI is hidden but the data is not cleared. Derived at save time, not from toggle alone, to handle the edge case where the user edits slots and then disables: in-progress edits are discarded, original DB slots are preserved.
- `**isPunishmentEnabled` (punishment text):** The `punishment` string on `Commitment` is never cleared when `isPunishmentEnabled` is false. The UI hides the text field when disabled, but the value is preserved.
- `**Target.isEnabled` (count):** `QuantifiedCycle` stores `count` and `isEnabled` together so the count survives toggling. The UI hides the count picker when disabled, but the value is preserved.

### Sequential phases, not parallel

**Decision:** Reminders → Punishment → Target, each fully complete (model + logic + UI) before moving on.

**Why not parallelize?** Each flag touches the same files (edit form, row view, detail view). Sequential delivery means each commit is independently testable and reviewable without merge conflicts.

---

## Major Model Changes


| Entity                                                                       | Change                                                                                                 |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `Shared/Models/Commitment.swift`                                             | `cycle: Cycle` added as top-level field; `isRemindersEnabled: Bool`, `isPunishmentEnabled: Bool` added |
| `Shared/Models/Commitment.swift` — `QuantifiedCycle`                         | `cycle: Cycle` removed; `isEnabled: Bool = true` added                                                 |
| `Shared/Models/Commitment.swift` — `StageCategory`                           | No new cases — `.current`, `.future`, `.others` reused for target-disabled path                        |
| `Shared/Scheduling/CommitmentAndSlot.swift`                                  | All three helpers filter `isRemindersEnabled`; new `remindersOnlyWithSlots()` helper (Commit 7)        |
| `Wilgo/Features/Stage/StageViewModel.swift`                                  | New `remindersOnly: [WithBehind]` property (Commit 7)                                                  |
| `Wilgo/Features/Commitments/FinishedCycleReport/Models.swift`                | `CycleReport` gains `isPunishmentEnabled: Bool`                                                        |
| `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift` | Uses `commitment.cycle`; sets `targetCheckIns = 0` when target disabled                                |


After restructure, the relevant shape of `Commitment` is:

```swift
var cycle: Cycle                    // always present — drives reporting
var target: Target                  // Target = QuantifiedCycle { count, isEnabled }
var punishment: String?             // always preserved
var isRemindersEnabled: Bool        // suppresses Stage view, notifications, Live Activity
var isPunishmentEnabled: Bool       // suppresses punishment enforcement
```

---

## Commit Plan

---

### Phase 1 — Move `Cycle` out of `Target` (pure refactor)

No behavior change. `Cycle` moves from `QuantifiedCycle` to a top-level field on `Commitment`. All callers and test fixtures are updated in a single commit. Tests must be green at the end of this phase.

---

#### Commit 1 — refactor: move Cycle to top-level Commitment field

Done in commit a22baeb9 and 8ef2ffe919

---

### Phase 2 — `isRemindersEnabled`

Full stack: model field → scheduling filter → Stage view → notifications → edit form → list display. Complete before Phase 3.

---

#### Commit 2 — feat: isRemindersEnabled — model + business logic

**Modify:** `Shared/Models/Commitment.swift`

Add field and init parameter (default `true`):

```swift
var isRemindersEnabled: Bool = true

init(..., isRemindersEnabled: Bool = true) {
    ...
    self.isRemindersEnabled = isRemindersEnabled
}
```

**Modify:** `Wilgo/Features/Stage/StageViewModel.swift`

Filter before passing to helpers in `recompute()`:

```swift
private func recompute() {
    let now = Date()
    let remindersOn = lastCommitments.filter { $0.isRemindersEnabled }
    current  = CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now)
    upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: remindersOn, after: now)
    catchUp  = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn, now: now)
}
```

**Modify:** `Wilgo/Features/Notifications/CatchUpReminder.swift`

Filter before the `catchUpWithBehind` call (same pattern — helpers stay pure):

```swift
let remindersOn = commitments.filter { $0.isRemindersEnabled }
let catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn, now: now)
```

**Create:** `WilgoTests/Commitment/CommitmentRemindersDisableTests.swift`

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment — isRemindersEnabled", .serialized)
final class CommitmentRemindersDisableTests {

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @MainActor
    private func makeCommitment(remindersEnabled: Bool, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: remindersEnabled
        )
        ctx.insert(c); ctx.insert(slot)
        return c
    }

    @Test("reminders disabled → helper still includes it (helpers are pure, no internal filter)")
    @MainActor func remindersDisabled_helperStillIncludes() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        // The helper classifies by slot timing, not by isRemindersEnabled.
        // Filtering is the caller's responsibility.
        #expect(CommitmentAndSlot.currentWithBehind(commitments: [c], now: now).count == 1)
    }

    @Test("reminders disabled → excluded after call-site filter (StageViewModel pattern)")
    @MainActor func remindersDisabled_excludedAfterCallSiteFilter() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let remindersOn = [c].filter { $0.isRemindersEnabled }
        #expect(CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now).isEmpty)
    }

    @Test("reminders enabled → included after call-site filter")
    @MainActor func remindersEnabled_includedAfterCallSiteFilter() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: true, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let remindersOn = [c].filter { $0.isRemindersEnabled }
        #expect(CommitmentAndSlot.currentWithBehind(commitments: remindersOn, now: now).count == 1)
    }

    @Test("reminders disabled → stageStatus itself is unaffected (filtering is upstream)")
    @MainActor func remindersDisabled_stageStatusUnchanged() throws {
        let container = try makeContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category == .current)
    }
}
```

**Run tests:**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4D4E7E2F-1CE5-4697-A734-85AB68DC55D4' \
  -only-testing WilgoTests/CommitmentRemindersDisableTests 2>&1 | tail -20
```

Expected: all 3 tests pass.

---

#### Commit 3 — feat: isRemindersEnabled — edit form + list display

**Modify:** `Wilgo/Features/Commitments/CommitmentFormFields.swift`

Add `@Binding var isRemindersEnabled: Bool`. Wrap `ReminderWindowsSection` in a toggle:

```swift
Section {
    Toggle("Reminders", isOn: $isRemindersEnabled)
    if isRemindersEnabled {
        ReminderWindowsSection(slotWindows: $slotWindows)
    }
} header: {
    Text("Reminder Windows")
} footer: {
    if !isRemindersEnabled {
        Text("No reminders. Commitment won't appear in Stage view or send notifications.")
    }
}
```

**Modify:** `Wilgo/Features/Commitments/AddCommitView.swift`

Add `@State private var isRemindersEnabled: Bool = true`. Pass to `CommitmentFormFields`. In `persistCommitment(grace:)`:

```swift
let commitment = Commitment(
    ...,
    slots: isRemindersEnabled ? sortedSlots : [],
    ...,
    isRemindersEnabled: isRemindersEnabled
)
```

**Modify:** `Wilgo/Features/Commitments/EditCommitmentView.swift`

Add `@State private var isRemindersEnabled: Bool`. In `init`: `_isRemindersEnabled = State(initialValue: commitment.isRemindersEnabled)`. Pass to `CommitmentFormFields`. In `saveChanges`: `commitment.isRemindersEnabled = isRemindersEnabled`.

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift`

Update reminder windows row:

```swift
Text(commitment.isRemindersEnabled ? slotWindowsSummary(commitment) : "Disabled")
    .font(.caption)
    .foregroundStyle(commitment.isRemindersEnabled ? .secondary : .tertiary)
```

**Manual verification:** Launch on iPhone 17 (`4D4E7E2F-1CE5-4697-A734-85AB68DC55D4`). Toggle Reminders off → slot windows disappear. Save → row shows "Disabled". Edit → toggle is off. Toggle back on → slot windows reappear.

---

### ~~Phase 3 — `isPunishmentEnabled`~~ — SKIPPED (2026-04-17)

**Decision:** Phase 3 is dropped entirely. `isPunishmentEnabled` will not be implemented.

**Why:** An empty `punishment` string is already semantically equivalent to "no punishment". A separate boolean toggle adds UI complexity and a new model field for no user-facing gain — the user can simply clear the punishment text to disable it. The preservation concern that motivated the flag (keeping the text alive while disabled) is not compelling enough to justify the extra surface.

---

#### Commit 4 — feat: isPunishmentEnabled — model + report

**Modify:** `Shared/Models/Commitment.swift`

Add field and init parameter (default `true`):

```swift
var isPunishmentEnabled: Bool = true

init(..., isRemindersEnabled: Bool = true, isPunishmentEnabled: Bool = true) {
    ...
    self.isPunishmentEnabled = isPunishmentEnabled
}
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/Models.swift`

Add `isPunishmentEnabled: Bool = true` to `CycleReport`.

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift`

Pass `isPunishmentEnabled: commitment.isPunishmentEnabled` when constructing `CycleReport`.

Find where the punishment page is conditionally shown in the report view (in `PositivityTokenPage.swift` or `CheckInSummaryPage.swift`) and gate it:

```swift
if cycleReport.isPunishmentEnabled {
    // punishment page content
}
```

---

#### Commit 5 — feat: isPunishmentEnabled — edit form + list/detail display

**Modify:** `Wilgo/Features/Commitments/CommitmentFormFields.swift`

Add `@Binding var isPunishmentEnabled: Bool`. Update Punishment section:

```swift
Section {
    Toggle("Enable punishment", isOn: $isPunishmentEnabled)
    if isPunishmentEnabled {
        TextField("e.g. Give robaroba 20 RMB", text: $punishment, axis: .vertical)
            .lineLimit(2...4)
    }
} header: {
    Text("Punishment if credits run out")
} footer: {
    Text(isPunishmentEnabled ? "Leave blank for no punishment."
         : "Punishment suppressed. Skip credits still consumed when target is missed.")
}
```

**Modify:** `Wilgo/Features/Commitments/AddCommitView.swift`

Add `@State private var isPunishmentEnabled: Bool = true`. Pass to `CommitmentFormFields`. In `persistCommitment`:

```swift
punishment: (isPunishmentEnabled && !trimmedPunishment.isEmpty) ? trimmedPunishment : nil,
isPunishmentEnabled: isPunishmentEnabled
```

**Modify:** `Wilgo/Features/Commitments/EditCommitmentView.swift`

Add `@State private var isPunishmentEnabled: Bool`. Load in `init`. Save in `saveChanges`.

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift`

Update punishment row:

```swift
let text: String = {
    if !commitment.isPunishmentEnabled { return "Disabled" }
    if let p = commitment.punishment, !p.isEmpty { return p }
    return "None"
}()
Text(text)
    .font(.caption)
    .foregroundStyle(commitment.isPunishmentEnabled ? .secondary : .tertiary)
```

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift`

Update `hasPunishment`:

```swift
private var hasPunishment: Bool {
    guard commitment.isPunishmentEnabled else { return false }
    return commitment.punishment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
}
```

**Manual verification:** Toggle Punishment off → text field disappears, footer explains PT still consumed. Save → row shows "Disabled". Toggle back on → previous text reappears.

---

### Phase 4 — `Target.isEnabled`

---

#### Commit 6 — feat: Target.isEnabled — model + stageStatus

**Modify:** `Shared/Models/Commitment.swift`

Add `isEnabled` to `QuantifiedCycle`:

```swift
struct QuantifiedCycle: Codable, Hashable {
    var count: Int
    var isEnabled: Bool = true
}
```

**No new `StageCategory` case.** `StageCategory` is unchanged — `.current`, `.future`, and `.others` are reused as-is. Target-disabled commitments produce the same categories as normal ones; the difference is that `behindCount` is always `0` and callers check `commitment.target.isEnabled` before rendering goal/behind UI.

Insert early exit at top of `stageStatus(now:)`:

```swift
func stageStatus(now: Date = Time.now()) -> StageStatus {
    if !target.isEnabled {
        return targetDisabledStatus(now: now)
    }
    // ... existing logic unchanged ...
}
```

Add private helper (today-only slot resolution, no goal math, `behindCount` always `0`):

```swift
private func targetDisabledStatus(now: Date) -> StageStatus {
    let cal = Time.calendar
    let nowPsychDay = Time.startOfDay(for: now)

    func resolveOccurrence(slot: Slot) -> Slot? {
        let start = Time.resolve(timeOfDay: slot.start, on: nowPsychDay)
        var end = Time.resolve(timeOfDay: slot.end, on: nowPsychDay)
        if end <= start { end = cal.date(byAdding: .day, value: 1, to: end) ?? end }
        guard slot.isActive(on: start, calendar: cal) else { return nil }
        let resolved = Slot(start: start, end: end)
        resolved.id = slot.id
        return resolved
    }

    var todaySlots = slots.compactMap { resolveOccurrence(slot: $0) }
    todaySlots.sort { $0.start < $1.start }

    let remaining = todaySlots.filter { occ in
        occ.end >= now &&
        !(slots.first { $0.id == occ.id }?.isSnoozed(at: now) ?? false)
    }

    guard let first = remaining.first else {
        return StageStatus(category: .others, nextUpSlots: [], behindCount: 0)
    }

    if first.start <= now {
        return StageStatus(category: .current, nextUpSlots: remaining, behindCount: 0)
    }
    return StageStatus(category: .future, nextUpSlots: remaining, behindCount: 0)
}
```

**Create:** `WilgoTests/Commitment/CommitmentTargetDisableTests.swift`

```swift
import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment — Target.isEnabled", .serialized)
final class CommitmentTargetDisableTests {

    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @MainActor
    private func makeCommitment(targetEnabled: Bool, slotHour: Int = 9, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: slotHour), end: tod(hour: slotHour + 2))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 3, isEnabled: targetEnabled)
        )
        ctx.insert(c); ctx.insert(slot)
        return c
    }

    @Test("target disabled + slot active now → .current (no goal math)")
    @MainActor func targetDisabled_slotActive_isCurrent() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)
        #expect(status.category == .current)
        #expect(status.behindCount == 0)
    }

    @Test("target disabled + slot in future today → .future with nextUpSlots")
    @MainActor func targetDisabled_slotFuture_isFuture() throws {
        let container = try makeContainer()
        let c = makeCommitment(targetEnabled: false, slotHour: 15, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.stageStatus(now: now)
        #expect(status.category == .future)
        #expect(!status.nextUpSlots.isEmpty)
        #expect(status.behindCount == 0)
    }

    @Test("target disabled + no slots today → .others")
    @MainActor func targetDisabled_noSlots_isOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [],
            target: Target(count: 3, isEnabled: false)
        )
        ctx.insert(c)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category == .others)
    }

    @Test("target disabled → never .metGoal even with sufficient check-ins")
    @MainActor func targetDisabled_manyCheckIns_notMetGoal() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(targetEnabled: false, in: ctx)
        let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 8))
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.stageStatus(now: now).category != .metGoal)
    }
}
```

**Run tests:**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4D4E7E2F-1CE5-4697-A734-85AB68DC55D4' \
  -only-testing WilgoTests/CommitmentTargetDisableTests 2>&1 | tail -20
```

Expected: all 4 tests pass.

---

#### Commit 7 — feat: Target.isEnabled — Stage view UI guard

No changes to `CommitmentAndSlot.swift` or `StageViewModel.swift`. After Commit 6, `stageStatus` on a target-disabled commitment already returns `.current`, `.future`, or `.others` — so the existing `currentWithBehind` / `upcomingWithBehind` / `catchUpWithBehind` functions pick them up naturally. `behindCount` is always `0` on that path.

The only change needed is to hide goal-related UI when the commitment has target disabled.

**Modify:** `CurrentCommitmentRow` (and the upcoming row, wherever behind badge / goal counter is rendered)

Gate goal-related UI on `commitment.target.isEnabled`:

```swift
if commitment.target.isEnabled {
    // behind badge, goal counter
}
```

**Run tests:**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4D4E7E2F-1CE5-4697-A734-85AB68DC55D4' \
  -only-testing WilgoTests/CommitmentTargetDisableTests 2>&1 | tail -20
```

**Manual verification:** Create a commitment with target disabled and a slot for today. It should appear in the normal current/upcoming section in Stage with no goal counter or behind badge.

---

#### Commit 8 — feat: Target.isEnabled — FinishedCycleReport

**UI design** (applies to both Page 1 `CheckInSummaryPage` and Page 2 `PositivityTokenPage`):


| State           | Icon                          | Body text                                                                                                                    |
| --------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Normal pass     | `checkmark.circle.fill` green | `"3/3 check-ins"`                                                                                                            |
| Normal fail     | `xmark.circle.fill` red       | `"1/3 check-ins"`                                                                                                            |
| Grace           | `shield.lefthalf.filled` gray | `"2/3 check-ins · grace"` — target still shown because grace is a *temporary suspension* of an active goal                   |
| Target disabled | `minus.circle` gray/tertiary  | `"2 check-ins · no target"` — no denominator because the stored count is a *saved default for next time*, not an active goal |


Grace and target-disabled are mechanically identical — no goal evaluation, no PT consumed — but semantically different: grace means "still your goal, just temporarily suspended"; target-disabled means "not a goal right now."

**PT rule:** Neither grace nor target-disabled cycles consume PT. PT only applies when a user has an active goal and fell short of it. Both states opt out of that evaluation entirely.

**Future refactor note (deferred):** `isGrace` and `Target.isEnabled = false` are largely overlapping concepts — grace is essentially "target disabled with a temporary end date." When target is disabled, `isGrace` has no meaningful distinction (a grace period on a disabled target is redundant). These two concepts should eventually be unified, but that is out of scope here.

**Design analysis for the future unification:**

The unified model would fold grace into `Target`/`QuantifiedCycle`:

```swift
// Option A — enum
enum TargetState {
    case enabled
    case disabled                    // permanent, no end date
    case suspended(until: Date)      // grace — temporary, end date known
}

// Option B — struct
struct TargetSuspension {
    var isEnabled: Bool
    var suspendedUntil: Date?        // nil = permanent disable, non-nil = grace
}
```

UI and report behavior falls out naturally:


| `isEnabled` | `suspendedUntil` | Report display                                                         | PT             |
| ----------- | ---------------- | ---------------------------------------------------------------------- | -------------- |
| `true`      | —                | `"3/3 check-ins"`                                                      | yes, if missed |
| `false`     | `nil`            | `"2 check-ins · no target"`                                            | no             |
| `false`     | some date        | `"2/3 check-ins · grace"` (target shown as it's still the active goal) | no             |


**The main blocker for deferral:** Grace is currently stored as `gracePeriods: [GracePeriod]` — a separate `@Relationship` on `Commitment`, not inside `QuantifiedCycle`. The refactor would need to migrate grace into `Target` where it semantically belongs, making it a SwiftData model migration — not just a rename.

---

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/Models.swift`

Add `isTargetEnabled: Bool` to `CycleReport` (analogous to `isGrace`), so views can branch without recomputing:

```swift
struct CycleReport: Identifiable {
    ...
    let isGrace: Bool
    let isTargetEnabled: Bool   // NEW
}
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift`

Pass `isTargetEnabled: commitment.target.isEnabled` when constructing `CycleReport`. Do **not** set `targetCheckIns` to 0 — keep the actual count so Grace can display `actual/target`. The view uses `isTargetEnabled` to decide whether to show the denominator.

```swift
CycleReport(
    ...
    targetCheckIns: draft.targetCheckIns,  // unchanged — real count preserved
    isTargetEnabled: commitment.target.isEnabled,
    isGrace: draft.isGrace
)
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/CheckInSummaryPage.swift`

Update `CheckInCycleRow` to handle the target-disabled state. The row currently branches on `isGrace`; add a new branch for `!isTargetEnabled`:

```swift
// icon
if cycle.isGrace {
    Image(systemName: "shield.lefthalf.filled")
        .foregroundStyle(.secondary)
} else if !cycle.isTargetEnabled {
    Image(systemName: "minus.circle")
        .foregroundStyle(.tertiary)
} else {
    Image(systemName: rawMetTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(rawMetTarget ? .green : .red)
}

// body text
if cycle.isGrace {
    Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins · grace")
        .font(.body)
        .foregroundStyle(.secondary)
} else if !cycle.isTargetEnabled {
    Text("\(cycle.actualCheckIns) check-ins · no target")
        .font(.body)
        .foregroundStyle(.tertiary)
} else {
    Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins")
        .font(.body)
}
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/PositivityTokenPage.swift`

Update `CycleResultRow` with the same branching logic. Also fix the existing inconsistency where grace cycles currently show a pass/fail icon on Page 2:

```swift
// icon
if cycle.isGrace {
    Image(systemName: "shield.lefthalf.filled")
        .foregroundStyle(.secondary)
} else if !cycle.isTargetEnabled {
    Image(systemName: "minus.circle")
        .foregroundStyle(.tertiary)
} else {
    Image(systemName: cycle.metTarget ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(cycle.metTarget ? .green : .red)
}

// body text
if cycle.isGrace {
    Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins · grace")
        .font(.body)
        .foregroundStyle(.secondary)
} else if !cycle.isTargetEnabled {
    Text("\(cycle.actualCheckIns) check-ins · no target")
        .font(.body)
        .foregroundStyle(.tertiary)
} else {
    Text("\(cycle.compensatedCheckIns)/\(cycle.targetCheckIns) check-ins")
        .font(.body)
}
```

**Modify:** `WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift`

Add test:

```swift
@Test("target disabled: isTargetEnabled false, targetCheckIns preserves real count, no PT")
@MainActor func targetDisabled_reportPreservesCount() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let anchor = date(year: 2026, month: 2, day: 1)
    let c = Commitment(
        title: "Draw",
        cycle: Cycle(kind: .daily, referencePsychDay: anchor),
        slots: [],
        target: Target(count: 3, isEnabled: false)
    )
    ctx.insert(c)
    let checkIn = CheckIn(commitment: c, createdAt: date(year: 2026, month: 2, day: 1, hour: 9))
    ctx.insert(checkIn)
    c.checkIns.append(checkIn)

    let preReport = PreTokenReportBuilder.build(
        commitments: [c],
        startPsychDay: date(year: 2026, month: 2, day: 1),
        endPsychDay: date(year: 2026, month: 2, day: 2)
    )

    #expect(preReport.count == 1)
    let cycle = try #require(preReport.first?.cycles.first)
    #expect(cycle.actualCheckIns == 1)
    #expect(cycle.targetCheckIns == 3)   // preserved, not zeroed out
    #expect(cycle.isTargetEnabled == false)
    #expect(cycle.consumedPTReasons.isEmpty)
}
```

**Run tests:**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4D4E7E2F-1CE5-4697-A734-85AB68DC55D4' \
  -only-testing WilgoTests/FinishedCycleReportBuilderTests 2>&1 | tail -20
```

---

#### Commit 9 — feat: Target.isEnabled — edit form + list/detail display

**Modify:** `Wilgo/Features/Commitments/CommitmentFormFields.swift`

Add `targetEnabledBinding`. Wrap count picker in toggle. The Punishment section remains always visible (Phase 3 was skipped — no `isPunishmentEnabled` flag exists):

```swift
Section("Target") {
    Toggle("Enable target", isOn: targetEnabledBinding)
    if target.isEnabled {
        HStack(spacing: 4) {
            Picker("", selection: targetCountBinding) {
                ForEach(0..<31, id: \.self) { Text("\($0)").tag($0) }
            }.labelsHidden()
            Text("every")
            Picker("", selection: targetCycleKindBinding) {
                ForEach(CycleKind.allCases, id: \.self) {
                    Text($0.rawValue.lowercased()).tag($0)
                }
            }.labelsHidden()
        }
    }
}

// Punishment section is unchanged — always visible regardless of target state.

private var targetEnabledBinding: Binding<Bool> {
    Binding(get: { target.isEnabled }, set: { target.isEnabled = $0 })
}
```

**Modify:** `Wilgo/Features/Commitments/AddCommitView.swift`

Default target: `@State private var target: Target = Target(count: 5, isEnabled: true)`. No changes needed to the punishment line — it was already not gated on `isPunishmentEnabled` (Phase 3 skipped).

Also guard `handleSaveTap` — when target is disabled at creation time, the grace dialog is meaningless (no goal to penalize against), so skip it. Uses the shared `GraceDialogState` (already on main):

```swift
private func handleSaveTap() {
    guard target.isEnabled else {
        persistCommitment(grace: false)
        return
    }
    let today = Time.startOfDay(for: Time.now())
    graceDialog.trigger(
        context: .creation,
        cycle: cycle,
        cycleStart: cycle.startDayOfCycle(including: today),
        cycleEnd: cycle.endDayOfCycle(including: today)
    )
}
```

**Modify:** `Wilgo/Features/Commitments/EditCommitmentView.swift`

`target` already carries `isEnabled` — no additional state needed. Verify `commitment.target = target` in `saveChanges` writes `isEnabled`.

**Grace dialog — re-enable only.** When the user re-enables a target (`false → true`), the current cycle may have already started without a target. Offer the grace dialog so the user can opt out of penalties for that partial cycle. Disabling (`true → false`) must **not** trigger the dialog — there is nothing to penalize when target is off.

Snapshot the original `isEnabled` in `init` alongside `originalTarget`:

```swift
private let originalTargetWasEnabled: Bool  // add alongside originalTarget

// in init:
originalTargetWasEnabled = commitment.target.isEnabled
```

Add a helper to detect re-enable:

```swift
/// True only when the target is being re-enabled this save.
private var targetBeingReEnabled: Bool {
    !originalTargetWasEnabled && target.isEnabled
}
```

Update `handleSaveTap` — skip the grace dialog when disabling, and use the correct `GraceDialogState.Context` for the re-enable case. Uses the shared `GraceDialogState` (already on main):

```swift
private func handleSaveTap() {
    guard anyRuleChanged else {
        saveChanges(grace: false)
        return
    }
    // Only offer grace when target is active after save (re-enable or count change while enabled).
    guard target.isEnabled else {
        saveChanges(grace: false)
        return
    }
    let newCycle = Cycle.makeDefault(cycle.kind)
    let today = Time.startOfDay(for: Time.now())
    let context: GraceDialogState.Context = targetBeingReEnabled
        ? .reEnable(targetCount: target.count)   // "Target re-enabled (N× per day)..."
        : .ruleChange(targetCount: target.count) // "Your goal changes to N per day now..."
    graceDialog.trigger(
        context: context,
        cycle: newCycle,
        cycleStart: newCycle.startDayOfCycle(including: today),
        cycleEnd: newCycle.endDayOfCycle(including: today)
    )
}
```

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift`

Update target row only. The punishment row is unchanged — no `isPunishmentEnabled` flag exists (Phase 3 skipped):

```swift
// Target row
if commitment.target.isEnabled {
    Text("\(commitment.target.count)× \(commitment.cycle.kind.adj)")
        .font(.caption).foregroundStyle(.secondary)
} else {
    Text("Disabled").font(.caption).foregroundStyle(.tertiary)
}

// Punishment row — no change needed
```

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift`

In `currentSection`, conditionally show denominator:

```swift
statTile(
    value: commitment.target.isEnabled
        ? "\(checkInsInCurrentTargetCycle.count)/\(commitment.target.count)"
        : "\(checkInsInCurrentTargetCycle.count)",
    label: commitment.target.isEnabled
        ? "Completed \(commitment.cycle.kind.thisNoun)"
        : "Check-ins \(commitment.cycle.kind.thisNoun)"
)
```

In `statsSection`, goal tile:

```swift
commitment.target.isEnabled
    ? statTile(value: "\(commitment.target.count)×", label: "\(commitment.cycle.kind.rawValue)\ngoal")
    : statTile(value: "—", label: "\(commitment.cycle.kind.rawValue)\ngoal disabled")
```

**Manual verification:**
- Toggle Target off → count picker disappears; Punishment section remains visible. Save → **no grace dialog** (disabling never triggers it). Target row shows "Disabled".
- Edit → toggle is off, count value preserved. Toggle back on → grace dialog appears with re-enable wording. Choosing "grace" exempts the current cycle. Choosing "committed" does not.
- Detail view shows "—" for goal tile when target is disabled.

---

#### Commit 10 — Full test suite

**Run:**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' 2>&1 | tail -50
```

Expected: all tests pass except pre-existing failure `stageStatus_snoozeDoesNotAffectFutureOccurrence` (known since 2026-04-14). Fix any unexpected failures before closing.

---

## Critical Files


| File                                                                         | Role                                   |
| ---------------------------------------------------------------------------- | -------------------------------------- |
| `Shared/Models/Commitment.swift`                                             | Model changes across all phases        |
| `Shared/Scheduling/CommitmentAndSlot.swift`                                  | Reminder filter + remindersOnly helper |
| `Wilgo/Features/Commitments/CommitmentFormFields.swift`                      | Toggle UI for all three parts          |
| `Wilgo/Features/Commitments/AddCommitView.swift`                             | Wires new state + passes to init       |
| `Wilgo/Features/Commitments/EditCommitmentView.swift`                        | Loads + saves new fields               |
| `Wilgo/Features/Stage/StageViewModel.swift`                                  | remindersOnly list                     |
| `Wilgo/Features/Commitments/FinishedCycleReport/PreTokenReportBuilder.swift` | Target-disabled report handling        |


### Dependency Graph

```
Commit 1: refactor — move Cycle to top-level Commitment field
    |
    +-- Commit 2: feat — isRemindersEnabled model + logic
    |       |
    |       +-- Commit 3: feat — isRemindersEnabled UI
    |               |
    |               +-- Commit 4: feat — isPunishmentEnabled model + report  [SKIPPED]
    |                       |
    |                       +-- Commit 5: feat — isPunishmentEnabled UI  [SKIPPED]
    |                               |
    |                               +-- Commit 6: feat — Target.isEnabled model + stageStatus
    |                                       |
    |                                       +-- Commit 7: feat — Target.isEnabled scheduling + Stage view
    |                                               |
    |                                               +-- Commit 8: feat — Target.isEnabled FinishedCycleReport
    |                                                       |
    |                                                       +-- Commit 9: feat — Target.isEnabled edit form + list/detail display
    |                                                               |
    |                                                               +-- Commit 10: full test suite
```

All commits are sequential. Each is independently buildable and testable.