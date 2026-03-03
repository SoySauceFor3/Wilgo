Great codebase — fairly clean for an early-stage SwiftUI/SwiftData app. Here's a thorough review organized by priority.

---

## Bugs / Correctness Issues

**1. `UpcomingHabitRow` uses raw `slot.start`/`slot.end`**

This is likely showing incorrect times. Every other place in the app uses `HabitScheduling.windowStartToday`/`windowEndToday` to project a slot's time-of-day onto today's date. `UpcomingHabitRow` skips that and formats the slot's arbitrary reference-date values directly.

**2. `skipCreditCount` is never decremented**

The Snooze button is disabled when `skipCreditCount <= 0`, but nothing ever decrements it — not on snooze, not at midnight. The guard is in place but the budget is never actually spent.

**3. `SnoozedSlot.resolvedAt` is never written**

Snoozes are created correctly, but `resolvedAt` (which should be stamped when a snoozed slot is eventually completed or expires) is always `nil`. The `StageEngine` missed-slot logic could benefit from this field being populated.

**4. `print()` debug statement in `StageEngine`**

Line 63 has `print("computeCurrentHabitSlots called...")` that should be removed before any real release.

---

## Typo — SwiftData Schema

**5. `pyschDay` → `psychDay`**

`HabitCheckIn.pyschDay` is a misspelling used consistently everywhere (`StageEngine`, check-in creation, etc.). It needs a SwiftData `VersionedSchema` + `SchemaMigrationPlan` to rename the stored column safely — can't just rename the property or existing data will break.

---

## Dead Code / Unused Files

**6. `Now/Now.swift` — entire file is dead code**

`NowBundle` only registers `NowLiveActivity()`. The static widget types (`Provider`, `SimpleEntry`, `NowEntryView`, `Now`) exist in `Now.swift` but are never registered and add confusion.

**7. `Shared/Models/Item.swift` — Xcode boilerplate**

This `@Model` with just a `timestamp: Date` is the Xcode new-project template scaffolding. It's registered in the `ModelContainer` schema, which means SwiftData is tracking a table for it unnecessarily.

---

## Architecture / Design

**8. `HabitScheduling.calendar` is captured once at launch**

```swift
static let calendar = Calendar.current
```

`Calendar.current` reflects the user's locale/timezone at the time it's first accessed. If the user changes their timezone while the app is backgrounded, all scheduling math will silently use the old calendar. It should be a `var` (or called inline).

**9. `windowStartToday` / `windowEndToday` are TODO-marked for removal but called everywhere**

These helpers in `HabitScheduling` have `// TODO: marked for removal` comments but are the primary way slots are resolved to today's date across `StageEngine`, `CurrentHabitRow`, `Missed`, and `PhaseEngine`. Either remove the TODO or replace them with whatever the intended successor API is — the ambiguity is a maintenance trap.

**10. `LiveActivityManager` has two competing sync paths**

`startMonitoring()` runs a background loop that wakes at each `nextTransitionDate`, and `sync()` is called imperatively from `StageView` on content-state changes and from `WilgoApp` on scene activation. Both call the same `apply()` internally so they don't conflict, but they can fire nearly simultaneously after a state change. A debounce or a single source of truth (e.g., only the background loop, with `sync()` just nudging it to wake early) would simplify reasoning.

**11. `ContentView.swift` naming**

The Habits list is still named `ContentView` — the Xcode default. This makes navigation confusing when reading `MainTabView`. Renaming to `HabitListView` (and moving it alongside `AddHabitView`) would match the feature-first structure the rest of the project uses.

---

## Minor

**12. CloudKit entitlement vs. local-only `ModelConfiguration`**

`Wilgo.entitlements` declares `icloud-services = [CloudKit]` but the `ModelContainer` is created with a plain local `ModelConfiguration`. If CloudKit sync isn't planned, the entitlement should be removed to avoid App Store review questions. If it is planned, the migration to `ModelConfiguration(cloudKitDatabase: .automatic)` should be tracked explicitly.

---

**Summary table:**

| #   | Issue                             | Risk if ignored          | Effort  |
| --- | --------------------------------- | ------------------------ | ------- |
| 1   | `UpcomingHabitRow` raw dates      | Wrong UI                 | Low     |
| 2   | Credits never decrement           | Core feature broken      | Medium  |
| 3   | `resolvedAt` never set            | Logic gap                | Low     |
| 4   | Debug `print()`                   | Noise                    | Trivial |
| 5   | `pyschDay` typo                   | Schema migration needed  | Medium  |
| 6   | `Now.swift` dead code             | Confusion                | Trivial |
| 7   | `Item.swift` dead code            | Extra SwiftData table    | Trivial |
| 8   | `Calendar.current` captured       | Timezone bug             | Low     |
| 9   | `windowStartToday` TODO ambiguity | Maintenance debt         | Low     |
| 10  | Dual LA sync paths                | Complexity               | Low     |
| 11  | `ContentView` naming              | Readability              | Trivial |
| 12  | CloudKit entitlement              | App Store / architecture | Low     |

Want me to go ahead and fix any of these? I'd suggest starting with items 1, 4, 6, 7, and 11 since they're trivially safe, then tackling 5 (the typo + migration) as a careful dedicated step.
