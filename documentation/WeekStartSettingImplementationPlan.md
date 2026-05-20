# Week Start Day — Implementation Plan

**PRD:** N/A  
**Tracking:** [allow choose Monday/Sunday as start of the week](https://www.notion.so/allow-choose-Monday-Sunday-as-start-of-the-week-3394b58e32c3803591b6ffe18fbea04e?source=copy_link)  
**Tag:** `#WeekStartSetting`

---

## Context

Weekly cycles are currently hardcoded to start on Monday in three places:

1. `Cycle.makeDefault(.weekly, ...)` — hardcodes `matches: 2` (Monday) as the anchor weekday when creating a new weekly commitment.
2. `Heatmap.WeeklyDataBuilder` — hardcodes a known Monday date as the fallback anchor for non-weekly commitments' heatmap view.
3. `CycleEndNotificationScheduler.trigger(for: .weekly)` — hardcodes `weekday = 2` (Monday) for the cycle-end notification trigger.

Users should be able to choose Monday or Sunday as the week start from Settings. When they change the setting and have existing weekly commitments, a confirmation sheet appears asking whether to make the current cycle (under the *new* week-start boundary) inspiration-only. If there are no affected weekly commitments, the setting applies silently.

---

## Architecture Summary

A new `UserDefaults` key `weekStartsOnMonday` (Bool, default `true`) is added to `AppSettings`. The three hardcoded Monday references above read this key at call time. `SettingsView` gets a segmented picker that — instead of binding directly to `@AppStorage` — triggers a re-anchor flow when the value changes. The re-anchor flow is a `WeekStartChangeHandler` value type (pure logic, no SwiftUI) that computes affected commitments and applies the inspiration-only mutation if requested. The sheet is presented in `SettingsView`.

---

## Design Decisions

### Bool vs. enum for the setting

**Decision:** `Bool` (`weekStartsOnMonday`). Only two options exist and they map cleanly to a boolean. Serialises trivially in `UserDefaults` / `@AppStorage`.

### Re-anchor on change, not at read time

**Decision:** When the user changes the setting, re-anchor existing weekly commitments immediately (mutating `commitment.cycle.referencePsychDay`). Do not try to "virtualise" the week-start at read time per-commitment.

**Why not virtualise?** Each `Commitment` stores its own `Cycle` with a concrete `referencePsychDay`. The entire cycle engine (period boundaries, heatmap, notifications) derives everything from that single anchor. Teaching the engine to "override" the anchor based on a global setting would require threading the setting through every call site — large change surface, high risk. Mutating `referencePsychDay` once at change time is clean.

### "Current cycle" is defined by the new week-start

**Decision:** When switching Mon→Sun on, say, a Thursday: the current cycle under the *new* (Sunday) week-start boundary is the Sunday that just passed through today. The sheet asks whether to make *that* period inspiration-only. The silently-abandoned closing Mon-start cycle is not surfaced.

**Why?** The user just decided they want Sun-start weeks. Showing them the old Mon-start closing cycle would be confusing — they've already rejected that boundary. What matters to them now is: "does this Sunday-to-today period count?"

### Inspiration-only: `start` and `until`

When the user picks "Yes" for inspiration-only, for each affected commitment:
- `start` = new week's start psych-day (most recent Sunday/Monday under the new setting, on or before today)
- `until` = new week's end psych-day (7 days after `start`) — so only this one cycle is inspiration-only; the following cycle returns to `.on`

This reuses the existing `target.setConfiguredMode(.inspirationOnly(start:until:))` mutation.

### No sheet when no affected commitments

If zero weekly commitments exist, the setting saves silently. No `referencePsychDay` mutation needed.

---

## Major Model Changes

| Entity | Change |
|--------|--------|
| `Shared/AppSettings.swift` | Add `weekStartsOnMondayKey` constant + `weekStartsOnMonday` computed accessor |
| `Shared/Models/Cycle.swift` | `makeDefault(.weekly, ...)` uses `AppSettings.weekStartsOnMonday` |
| `Wilgo/Features/Commitments/SingleCommitment/Heatmap/Data.swift` | `WeeklyDataBuilder` fallback anchor uses `AppSettings.weekStartsOnMonday` |
| `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` | Weekly trigger weekday uses `AppSettings.weekStartsOnMonday` |
| `Wilgo/Features/Settings/SettingsView.swift` | Week-start picker with re-anchor sheet (lands in Commit 2) |
| `Wilgo/Features/Settings/WeekStartChangeHandler.swift` *(new)* | Pure logic: compute affected commitments, apply re-anchor + inspiration-only |
| `WilgoTests/CycleMakeDefaultTests.swift` | Tests for Sunday-start behaviour |
| `WilgoTests/Settings/WeekStartChangeHandlerTests.swift` *(new)* | Tests for re-anchor and inspiration-only logic |

---

## Commit Plan

### Phase 1 — Core logic + Settings UI picker (no sheet yet)

#### Commit 1 — Add `weekStartsOnMonday` accessor; update `Cycle.makeDefault`, heatmap, notifications, and Settings picker

**Modify:** `Shared/AppSettings.swift`  
Add after the existing key constants:

```swift
/// Whether the week starts on Monday (true) or Sunday (false). Default: true.
static let weekStartsOnMondayKey = "weekStartsOnMonday"

/// Reads the week-start preference from UserDefaults. Returns `true` (Monday) when the key is absent.
static var weekStartsOnMonday: Bool {
    UserDefaults.standard.object(forKey: weekStartsOnMondayKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: weekStartsOnMondayKey)
}

/// The Calendar weekday integer for the configured week-start day (1 = Sunday, 2 = Monday).
static var weekStartWeekday: Int { weekStartsOnMonday ? 2 : 1 }
```

**Modify:** `Shared/Models/Cycle.swift`  
Add a warning comment on the `multiplier` field (inside the `Cycle` struct definition):

```swift
// Before:
var multiplier: Int

// After:
// NOTE: multiplier > 1 is unused. Bi-weekly+ cycles conflict with the global
// weekStartsOnMonday setting — changing week-start cannot unambiguously re-anchor
// a multi-week block. Do not use multiplier > 1 until this is resolved.
var multiplier: Int
```

Change the `.weekly` branch of `makeDefault(_:on:)`:

```swift
// Before:
case .weekly:
    anchor = weeklyPeriodStart(matches: 2, of: psychDay)

// After:
case .weekly:
    anchor = weeklyPeriodStart(matches: AppSettings.weekStartWeekday, of: psychDay)
```

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/Heatmap/Data.swift`  
In `WeeklyDataBuilder.weeklyPeriods()`, replace the hardcoded Monday date:

```swift
// Before:
return Cycle(
    kind: .weekly,
    referencePsychDay: Time.calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 2))!)  // 03/02/2026 is a Monday

// After:
// weekStartWeekday: 2=Mon → anchor 2026-03-02 (Monday); 1=Sun → anchor 2026-03-01 (Sunday)
let anchorComponents = AppSettings.weekStartWeekday == 2
    ? DateComponents(year: 2026, month: 3, day: 2)
    : DateComponents(year: 2026, month: 3, day: 1)
return Cycle(
    kind: .weekly,
    referencePsychDay: Time.calendar.date(from: anchorComponents)!)
```

**Modify:** `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift`  
In `trigger(for:)`, change the `.weekly` case:

```swift
// Before:
case .weekly:
    components.weekday = 2 // Monday

// After:
case .weekly:
    components.weekday = AppSettings.weekStartWeekday
```

**Modify:** `Wilgo/Features/Settings/SettingsView.swift`  
Add `@AppStorage` and `@Environment` properties:

```swift
@AppStorage(AppSettings.weekStartsOnMondayKey)
private var weekStartsOnMonday: Bool = true

@Environment(\.modelContext) private var modelContext
```

Add the Calendar section inside the `Form`, after the Positivity Tokens section and before Tags. At this stage the picker writes directly to `@AppStorage` — the re-anchor sheet is added in Commit 3:

```swift
Section {
    Picker("Week starts on", selection: $weekStartsOnMonday) {
        Text("Monday").tag(true)
        Text("Sunday").tag(false)
    }
    .pickerStyle(.segmented)
} header: {
    Text("Calendar")
} footer: {
    Text("Sets the first day of the week for new weekly commitments and the weekly heatmap view.")
}
```

**Modify:** `WilgoTests/CycleMakeDefaultTests.swift`  
Add at the end of `CycleMakeDefaultTests`:

```swift
// MARK: Weekly — week-start setting

@Test("weekly: Sunday-start: Monday input returns prior Sunday")
func weeklyOnMondayReturnsPriorSundayWhenSettingIsSunday() {
    UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
    defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

    let monday = date(year: 2026, month: 3, day: 30)  // Monday
    let sunday = date(year: 2026, month: 3, day: 29)  // Prior Sunday
    let cycle = Cycle.makeDefault(.weekly, on: monday)
    #expect(cycle.startDayOfCycle(including: monday) == sunday)
}

@Test("weekly: Sunday-start: Wednesday input returns prior Sunday")
func weeklyOnWednesdayReturnsPriorSundayWhenSettingIsSunday() {
    UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
    defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

    let wednesday = date(year: 2026, month: 4, day: 1)
    let sunday = date(year: 2026, month: 3, day: 29)
    let cycle = Cycle.makeDefault(.weekly, on: wednesday)
    #expect(cycle.startDayOfCycle(including: wednesday) == sunday)
}

@Test("weekly: Monday-start still works when setting explicitly true")
func weeklyExplicitMondayStartReturnsMonday() {
    UserDefaults.standard.set(true, forKey: AppSettings.weekStartsOnMondayKey)
    defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

    let wednesday = date(year: 2026, month: 4, day: 1)
    let monday = date(year: 2026, month: 3, day: 30)
    let cycle = Cycle.makeDefault(.weekly, on: wednesday)
    #expect(cycle.startDayOfCycle(including: wednesday) == monday)
}

@Test("weekly: default (key absent) behaves as Monday-start")
func weeklyDefaultWithNoKeyIsMonday() {
    UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey)

    let wednesday = date(year: 2026, month: 4, day: 1)
    let monday = date(year: 2026, month: 3, day: 30)
    let cycle = Cycle.makeDefault(.weekly, on: wednesday)
    #expect(cycle.startDayOfCycle(including: wednesday) == monday)
}
```

**Manual verification:** Open Settings on the simulator. Confirm the "Calendar" section appears with a Monday/Sunday segmented control. Toggle it and relaunch — confirm the value persists. (Re-anchor sheet not yet wired up.)

Run tests:
```
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing:WilgoTests/CycleMakeDefaultTests
```
Expected: all `CycleMakeDefaultTests` pass (including the 4 new ones).

```
git add Shared/AppSettings.swift \
        Shared/Models/Cycle.swift \
        Wilgo/Features/Commitments/SingleCommitment/Heatmap/Data.swift \
        Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift \
        Wilgo/Features/Settings/SettingsView.swift \
        WilgoTests/CycleMakeDefaultTests.swift
git commit -m "feat: add weekStartsOnMonday setting; plumb into Cycle, heatmap, notifications, and Settings picker #WeekStartSetting

tracking: https://www.notion.so/allow-choose-Monday-Sunday-as-start-of-the-week-3394b58e32c3803591b6ffe18fbea04e"
```

---

### Phase 2 — Re-anchor logic + wire up sheet

#### Commit 2 — `WeekStartChangeHandler`: compute and apply the re-anchor

**Create:** `Wilgo/Features/Settings/WeekStartChangeHandler.swift`

```swift
import Foundation

/// Pure logic for applying a week-start change to existing weekly commitments.
struct WeekStartChangeHandler {

    /// Commitments whose cycle anchor will shift when `newStartsOnMonday` is applied.
    /// Returns only weekly commitments whose current `referencePsychDay` weekday
    /// does not already match the new week-start day.
    static func affectedCommitments(
        _ commitments: [Commitment],
        newStartsOnMonday: Bool
    ) -> [Commitment] {
        let targetWeekday = newStartsOnMonday ? 2 : 1
        let cal = Time.calendar
        return commitments.filter { c in
            guard c.cycle.kind == .weekly else { return false }
            let currentAnchorWeekday = cal.component(.weekday, from: c.cycle.referencePsychDay)
            return currentAnchorWeekday != targetWeekday
        }
    }

    /// The start of the current cycle under the *new* week-start boundary (on or before today).
    static func newCurrentCycleStart(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        let newCycle = Cycle.makeDefault(.weekly, on: today)
        return newCycle.startDayOfCycle(including: today)
    }

    /// The exclusive end of the current cycle under the new week-start boundary.
    static func newCurrentCycleEnd(newStartsOnMonday: Bool, today: Date = Time.now()) -> Date {
        let newCycle = Cycle.makeDefault(.weekly, on: today)
        return newCycle.endDayOfCycle(including: today)
    }

    /// Applies the week-start change to `commitments`:
    /// 1. Updates each commitment's `cycle.referencePsychDay` to align with the new week-start.
    /// 2. If `makeCurrentCycleInspirationOnly` is true, sets the current cycle
    ///    (under the new boundary) as inspiration-only for each commitment.
    static func apply(
        to commitments: [Commitment],
        newStartsOnMonday: Bool,
        makeCurrentCycleInspirationOnly: Bool,
        today: Date = Time.now()
    ) {
        let cycleStart = newCurrentCycleStart(newStartsOnMonday: newStartsOnMonday, today: today)
        let cycleEnd = newCurrentCycleEnd(newStartsOnMonday: newStartsOnMonday, today: today)

        for commitment in commitments {
            // Re-anchor to the new week-start. Preserves multiplier, but note:
            // multiplier > 1 is unused — re-anchoring a multi-week block is ambiguous.
            commitment.cycle = Cycle(
                kind: .weekly,
                referencePsychDay: cycleStart,
                multiplier: commitment.cycle.multiplier
            )
            // Optionally mark the current new-boundary cycle as inspiration-only.
            if makeCurrentCycleInspirationOnly {
                commitment.target.setConfiguredMode(
                    .inspirationOnly(start: cycleStart, until: cycleEnd)
                )
            }
        }
    }
}
```

**Create:** `WilgoTests/Settings/WeekStartChangeHandlerTests.swift`

```swift
import Foundation
import Testing
@testable import Wilgo

private func date(year: Int, month: Int, day: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = 0; c.minute = 0; c.second = 0
    return Calendar.current.date(from: c)!
}

// Minimal stub — WeekStartChangeHandler only needs cycle and target, not SwiftData persistence.
private func makeWeeklyCommitment(anchoredOn anchor: Date) -> Commitment {
    Commitment(
        title: "Test",
        cycle: Cycle(kind: .weekly, referencePsychDay: anchor),
        target: Target(count: 3),
        slots: []
    )
}

struct WeekStartChangeHandlerTests {

    // MARK: affectedCommitments

    @Test("affectedCommitments: Mon-anchored commitment is affected when switching to Sunday")
    func monAnchoredAffectedWhenSwitchingToSunday() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let monday = date(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.count == 1)
    }

    @Test("affectedCommitments: Sun-anchored commitment is not affected when switching to Sunday")
    func sunAnchoredNotAffectedWhenSwitchingToSunday() {
        let sunday = date(year: 2026, month: 3, day: 29)
        let c = makeWeeklyCommitment(anchoredOn: sunday)
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.isEmpty)
    }

    @Test("affectedCommitments: daily commitment is never affected")
    func dailyCommitmentNotAffected() {
        let today = date(year: 2026, month: 3, day: 30)
        let c = Commitment(
            title: "Daily",
            cycle: Cycle(kind: .daily, referencePsychDay: today),
            target: Target(count: 1),
            slots: []
        )
        let affected = WeekStartChangeHandler.affectedCommitments([c], newStartsOnMonday: false)
        #expect(affected.isEmpty)
    }

    // MARK: newCurrentCycleStart / newCurrentCycleEnd

    @Test("newCurrentCycleStart: Thursday → prior Sunday when switching to Sunday-start")
    func cycleStartThursdayToSunday() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let thursday = date(year: 2026, month: 4, day: 2)
        let expectedSunday = date(year: 2026, month: 3, day: 29)
        let start = WeekStartChangeHandler.newCurrentCycleStart(
            newStartsOnMonday: false, today: thursday)
        #expect(start == expectedSunday)
    }

    @Test("newCurrentCycleEnd: 7 days after start")
    func cycleEndIsSevenDaysAfterStart() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let thursday = date(year: 2026, month: 4, day: 2)
        let start = WeekStartChangeHandler.newCurrentCycleStart(
            newStartsOnMonday: false, today: thursday)
        let end = WeekStartChangeHandler.newCurrentCycleEnd(
            newStartsOnMonday: false, today: thursday)
        let diff = Calendar.current.dateComponents([.day], from: start, to: end).day!
        #expect(diff == 7)
    }

    // MARK: apply

    @Test("apply: re-anchors commitment to new cycle start")
    func applyReanchorsCommitment() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let monday = date(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let thursday = date(year: 2026, month: 4, day: 2)
        let expectedSunday = date(year: 2026, month: 3, day: 29)

        WeekStartChangeHandler.apply(
            to: [c], newStartsOnMonday: false,
            makeCurrentCycleInspirationOnly: false, today: thursday)

        #expect(c.cycle.referencePsychDay == expectedSunday)
    }

    @Test("apply: sets inspiration-only when requested")
    func applySetInspirationOnly() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let monday = date(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let thursday = date(year: 2026, month: 4, day: 2)
        let expectedStart = date(year: 2026, month: 3, day: 29)
        let expectedEnd = date(year: 2026, month: 4, day: 5)

        WeekStartChangeHandler.apply(
            to: [c], newStartsOnMonday: false,
            makeCurrentCycleInspirationOnly: true, today: thursday)

        if case let .inspirationOnly(start, until) = c.target.configuredMode {
            #expect(start == expectedStart)
            #expect(until == expectedEnd)
        } else {
            Issue.record("Expected inspirationOnly, got \(c.target.configuredMode)")
        }
    }

    @Test("apply: does not set inspiration-only when not requested")
    func applyNoInspirationOnly() {
        UserDefaults.standard.set(false, forKey: AppSettings.weekStartsOnMondayKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.weekStartsOnMondayKey) }

        let monday = date(year: 2026, month: 3, day: 30)
        let c = makeWeeklyCommitment(anchoredOn: monday)
        let thursday = date(year: 2026, month: 4, day: 2)

        WeekStartChangeHandler.apply(
            to: [c], newStartsOnMonday: false,
            makeCurrentCycleInspirationOnly: false, today: thursday)

        #expect(c.target.configuredMode == .on)
    }
}
```

Run tests:
```
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing:WilgoTests/WeekStartChangeHandlerTests
```
Expected: all 8 tests pass.

```
git add Wilgo/Features/Settings/WeekStartChangeHandler.swift \
        WilgoTests/Settings/WeekStartChangeHandlerTests.swift
git commit -m "feat: add WeekStartChangeHandler for re-anchoring weekly commitments #WeekStartSetting

tracking: https://www.notion.so/allow-choose-Monday-Sunday-as-start-of-the-week-3394b58e32c3803591b6ffe18fbea04e"
```

---

### Phase 3 — Wire up re-anchor sheet in `SettingsView`

#### Commit 3 — Replace direct `@AppStorage` binding with change-handler flow; add sheet

The picker section was added in Commit 1 using a simple `$weekStartsOnMonday` binding. This commit replaces the picker's `selection` with a custom `Binding` that intercepts changes and triggers the re-anchor sheet when there are affected commitments.

**Modify:** `Wilgo/Features/Settings/SettingsView.swift`

Add new `@State` properties (alongside the existing ones added in Commit 1):

```swift
@State private var pendingWeekStart: Bool? = nil
@State private var showWeekStartSheet = false
```

Replace the Calendar section's `Picker` binding — change `selection: $weekStartsOnMonday` to a custom binding:

```swift
Section {
    Picker("Week starts on", selection: Binding(
        get: { weekStartsOnMonday },
        set: { newValue in
            guard newValue != weekStartsOnMonday else { return }
            let all = (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? []
            let affected = WeekStartChangeHandler.affectedCommitments(all, newStartsOnMonday: newValue)
            if affected.isEmpty {
                weekStartsOnMonday = newValue
                CycleEndNotificationScheduler.refresh()
            } else {
                pendingWeekStart = newValue
                showWeekStartSheet = true
            }
        }
    )) {
        Text("Monday").tag(true)
        Text("Sunday").tag(false)
    }
    .pickerStyle(.segmented)
} header: {
    Text("Calendar")
} footer: {
    Text("Sets the first day of the week for new weekly commitments and the weekly heatmap view.")
}
```

Add computed properties used by the sheet:

```swift
private var pendingCycleStart: Date {
    guard let pending = pendingWeekStart else { return Time.now() }
    return WeekStartChangeHandler.newCurrentCycleStart(newStartsOnMonday: pending)
}

private var pendingCycleEnd: Date {
    guard let pending = pendingWeekStart else { return Time.now() }
    return WeekStartChangeHandler.newCurrentCycleEnd(newStartsOnMonday: pending)
}

private func dateRangeLabel(start: Date, end: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    let cal = Time.calendar
    let inclusiveEnd = cal.date(byAdding: .day, value: -1, to: end) ?? end
    return "\(fmt.string(from: start)) – \(fmt.string(from: inclusiveEnd))"
}
```

Add `.sheet` modifier on the `Form`:

```swift
.sheet(isPresented: $showWeekStartSheet) {
    weekStartSheet
}
```

Add the sheet view as a computed property:

```swift
.sheet(isPresented: $showWeekStartSheet) {
    weekStartSheet
}
```

Add the sheet view as a computed property:

```swift
@ViewBuilder
private var weekStartSheet: some View {
    let affected = affectedWeeklyCommitments
    let start = pendingCycleStart
    let end = pendingCycleEnd

    NavigationStack {
        VStack(alignment: .leading, spacing: 20) {
            Text(
                "Make the current cycle (\(dateRangeLabel(start: start, end: end))) inspiration only?"
            )
            .font(.body)

            if !affected.isEmpty {
                Text("Affected commitments:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(affected) { c in
                    Text("• \(c.title)")
                        .font(.subheadline)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Yes — make it inspiration only") {
                    applyWeekStartChange(inspirationOnly: true)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("No — just switch") {
                    applyWeekStartChange(inspirationOnly: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .navigationTitle("Week Start Change")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    pendingWeekStart = nil
                    showWeekStartSheet = false
                }
            }
        }
    }
    .presentationDetents([.medium])
}

private func applyWeekStartChange(inspirationOnly: Bool) {
    guard let newValue = pendingWeekStart else { return }
    let all = (try? modelContext.fetch(FetchDescriptor<Commitment>())) ?? []
    let affected = WeekStartChangeHandler.affectedCommitments(all, newStartsOnMonday: newValue)
    WeekStartChangeHandler.apply(
        to: affected,
        newStartsOnMonday: newValue,
        makeCurrentCycleInspirationOnly: inspirationOnly
    )
    weekStartsOnMonday = newValue
    pendingWeekStart = nil
    showWeekStartSheet = false
    CycleEndNotificationScheduler.refresh()
}
```

**Manual verification:**  
1. Open Settings on the iPhone 17 simulator (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`).
2. With at least one weekly commitment: tap Sunday → sheet appears showing the current cycle date range and the commitment name(s). Tap "Yes" → commitment gains inspiration-only for that cycle. Tap the picker again (back to Monday) → "No" → no inspiration-only. Tap Cancel → setting reverts.
3. With no weekly commitments: tapping Sunday applies instantly with no sheet.

```
git add Wilgo/Features/Settings/SettingsView.swift
git commit -m "feat: wire re-anchor sheet into week-start picker in SettingsView #WeekStartSetting

tracking: https://www.notion.so/allow-choose-Monday-Sunday-as-start-of-the-week-3394b58e32c3803591b6ffe18fbea04e"
```

---

## Critical Files

| File | Role |
|------|------|
| `Shared/AppSettings.swift` | New UserDefaults key |
| `Shared/Models/Cycle.swift` | Core weekly anchor logic |
| `Wilgo/Features/Commitments/SingleCommitment/Heatmap/Data.swift` | Heatmap weekly fallback anchor |
| `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` | Cycle-end notification weekday |
| `Wilgo/Features/Settings/WeekStartChangeHandler.swift` *(new)* | Re-anchor + inspiration-only logic |
| `Wilgo/Features/Settings/SettingsView.swift` | Settings UI + sheet |
| `WilgoTests/CycleMakeDefaultTests.swift` | Unit tests for Sunday-start makeDefault |
| `WilgoTests/Settings/WeekStartChangeHandlerTests.swift` *(new)* | Unit tests for re-anchor logic |

---

## Dependency Graph

```
Commit 1: AppSettings accessor + Cycle + Heatmap + Notifications + Settings picker (simple binding)
    |
    +-- Commit 2: WeekStartChangeHandler + tests  [after 1]
            |
            +-- Commit 3: Wire re-anchor sheet into picker  [after 2]
```

Linear chain — each commit depends on the previous. Commit 1 ships a functional (though un-guarded) picker immediately; Commit 3 upgrades it to the full sheet flow.
