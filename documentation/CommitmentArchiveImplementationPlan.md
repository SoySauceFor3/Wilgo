# Commitment Archive — Implementation Plan

**PRD:** [Archived list](https://www.notion.so/Archived-list-3664b58e32c380588108cacca6aca031)  
**Tracking:** [Allow Archive of a commitment](https://www.notion.so/Allow-Archive-of-a-commitment-3414b58e32c38096ab35c5471084c8c1)  
**Tag:** #CommitmentArchive

---

## Context

Users currently can only delete commitments, which permanently destroys check-in history. This feature adds archive support: swipe-left on the active list archives a commitment (hides it, preserves all data). Delete is only available from the archived list — an intentional friction gate. Archiving a commitment immediately stops all its notifications. Unarchiving restores it with all config intact and re-anchors the cycle to today.

A secondary fix is included: all callers of commitment mutation (add, edit, delete/archive) currently only call a subset of schedulers/widget refresh. This plan unifies them into a single `CommitmentChangeRefresher.refreshAll()`. Additionally, several places fetch all commitments unfiltered and must be updated to exclude archived ones: `StageView`, `FinishedCycleReportView` and `FinishedCycleReportModifier` (FCR), all notification/LA schedulers (`SlotStartNotificationScheduler`, `CatchUpReminder`, `CycleEndNotificationScheduler`, `NowLiveActivityManager`), and `SettingsView`'s week-start change handler.

> Note: this plan was written before the FCR redesign (`#FCRRedesign`) landed, which removed `TargetMode.inspirationOnly` and replaced `CheckInSummaryStep` with `FCRCycleCardView`. References below are updated to match the current codebase.

---

## Architecture Summary

- Add `archivedAt: Date?` to `Commitment`. `nil` = active, non-nil = archived. No manual SwiftData migration needed for optional fields.
- `ListCommitmentView`, `StageView`, and `FinishedCycleReportView` filter to `archivedAt == nil`. Swipe-left on the active list becomes "Archive" (not Delete).
- A `NavigationLink` row between the tag chips and commitment rows pushes `ArchivedCommitmentsView`.
- `ArchivedCommitmentsView` filters to `archivedAt != nil`, sorted by `archivedAt` descending. Swipe actions: "Unarchive" + "Delete" (with confirmation alert).
- `CommitmentDetailView` gains an `isArchived` flag: hides Current cycle section and Edit toolbar button when true. History (heatmap, both backfill entry points, delete check-in) and Past Cycles remain visible and interactive regardless.
- New `CommitmentChangeRefresher` enum with a single `refreshAll()` static method consolidates all 5 side-effect calls.

---

## Design Decisions

### Archive-first, delete-second

**Decision:** Swipe-left on active list = Archive only. Delete only available from archived list.

**Why not expose both on the active list?** Check-in history loss is irreversible. Even if a user never discovers the archive, the data accumulation is negligible. Archive-first prevents accidental permanent loss.

### Entry point: NavigationLink row between chips and list

**Decision:** Subtle secondary `NavigationLink` between `TagFilterChipsView` and the commitment rows.

**Why not toolbar / tab / settings?** Toolbar is already crowded (`+` and `Edit`). A 5th tab over-weights an infrequently used screen. Settings is for configuration, not data. This placement is always visible, doesn't touch the toolbar, and is contextually adjacent to the list.

### CommitmentChangeRefresher

**Decision:** Extract all post-mutation side effects into a single `CommitmentChangeRefresher.refreshAll()`.

**Why?** `EditCommitmentView` and `ListCommitmentView` currently only call `SlotStartNotificationScheduler.refresh()` + widget reload, missing `CatchUpReminder` and `CycleEndNotificationScheduler`. This is a pre-existing gap. The archive feature is the right moment to fix it consistently.

**Risk:** `NowLiveActivityManager.workAndScheduleNextBGTask()` is async-ish internally — verify it doesn't cause issues when called on the main thread from SwiftUI actions. **Mitigation:** Check existing call sites for threading context; wrap in `Task { }` if needed.

### Archived detail view: read-only for configuration only

**Decision:** Archived `CommitmentDetailView` hides the Current cycle section and the Edit toolbar button. Target mode display (`.on` / `.disabled`) is shown as-is (same as active list). **History stays fully interactive**: both backfill entry points (the overall "Backfill a Check-in" button and the heatmap info card's "Add Check-in"), the heatmap info card's delete-check-in action, and the "Past Cycles" (`CycleRecord`) section all remain visible and usable.

**Why hide Current cycle and Edit, but not history actions?** Current cycle target tracking and Edit are *configuration* — meaningless/frozen for an inactive commitment. Backfilling or deleting a check-in, and viewing past cycle outcomes, are corrections/views of *historical data*, which is the most valuable part of an archived commitment and which we explicitly chose to preserve. There's no harm in letting the user fix up history on an archived commitment, and blocking it would be a confusing, unexplainable restriction.

### Unarchive: cycle re-anchor

**Decision:** On unarchive, call `commitment.cycle = Cycle.makeDefault(commitment.cycle.kind)` to re-anchor the cycle to today.

**Why?** The stored `referencePsychDay` may be stale. Re-anchoring matches the behavior of `EditCommitmentView` on a rule change, and starts the current cycle fresh without wiping history.

### Filter archived everywhere commitments are fetched

**Decision:** Add `archivedAt == nil` predicate/filter everywhere commitments are fetched for active use: `StageView`, `FinishedCycleReportView` (`@Query`), `FinishedCycleReportModifier` (2 `FetchDescriptor` call sites), `SlotStartNotificationScheduler`, `CatchUpReminder`, `CycleEndNotificationScheduler`, `NowLiveActivityManager` (2 call sites), and `SettingsView` (week-start change handler).

**Why?** Archived commitments are frozen and inactive — they must not appear in the Today dashboard, cycle-end reports, scheduled notifications, Live Activity, or be mutated by week-start changes.

**Week-start note:** `WeekStartChangeHandler.apply()` re-anchors `commitment.cycle` to the new week-start boundary. Archived commitments should be excluded — re-anchoring a frozen commitment's cycle is pointless churn. On unarchive, `Cycle.makeDefault` re-anchors the cycle to the current week-start anyway, so no staleness is introduced.

---

## Major Model Changes

| Entity | Change |
|---|---|
| `Shared/Models/Commitment.swift` | Add `var archivedAt: Date?` |
| **New:** `Wilgo/Shared/CommitmentChangeRefresher.swift` | Static `refreshAll()` consolidating all 5 side-effect calls |
| **New:** `Shared/Models/Commitment+FetchDescriptor.swift` | `FetchDescriptor<Commitment>.activeOnly` extension |
| `Wilgo/Features/Commitments/ListCommitmentView.swift` | Filter query, replace onDelete with Archive swipe, add NavigationLink row |
| `Wilgo/Features/Stage/StageView.swift` | Filter query to exclude archived |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift` | Filter `@Query` to exclude archived |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift` | Filter both `FetchDescriptor` fetches to exclude archived |
| `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | Filter fetch to exclude archived |
| `Wilgo/Features/Notifications/CatchUpReminder.swift` | Filter fetch to exclude archived |
| `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` | Filter fetch to exclude archived |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | Filter both fetches to exclude archived |
| `Wilgo/Features/Settings/SettingsView.swift` | Filter week-start handler fetch to exclude archived |
| **New:** `Wilgo/Features/Commitments/ArchivedCommitmentsView.swift` | Archived list screen |
| `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift` | Add `isArchived` flag, conditionally hide sections |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift` | Replace partial refresh with `CommitmentChangeRefresher.refreshAll()` |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift` | Replace partial refresh with `CommitmentChangeRefresher.refreshAll()` |

---

## Commit Plan

### Phase 1 — Foundation (no UI changes, must land first)

#### Commit 1 — add `archivedAt` to Commitment model #CommitmentArchive

**Modify:** `Shared/Models/Commitment.swift`  
Add after `createdAt`:

```swift
var archivedAt: Date?
```

No migration file needed — SwiftData handles new optional fields automatically.

**Create:** `WilgoTests/Commitment/CommitmentArchiveTests.swift`  
Tests:
- New commitment has `archivedAt == nil`
- Setting `archivedAt` to a date persists and round-trips through save/fetch
- Two commitments can independently have `archivedAt` set or nil

**Manual verification:** Launch app on iPhone 17 simulator (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`). App must launch without crash and existing commitments must appear unchanged.

---

#### Commit 2 — extract CommitmentChangeRefresher #CommitmentArchive

**Depends on:** nothing (independent of Commit 1, can be parallel)

**Create:** `Wilgo/Shared/CommitmentChangeRefresher.swift`

```swift
import SwiftUI
import WidgetKit

enum CommitmentChangeRefresher {
    static func refreshAll() {
        SlotStartNotificationScheduler.refresh()
        CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
        CycleEndNotificationScheduler.refresh()
        NowLiveActivityManager.workAndScheduleNextBGTask()
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
    }
}
```

**Modify:** `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`  
Replace:
```swift
WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
SlotStartNotificationScheduler.refresh()
```
With:
```swift
CommitmentChangeRefresher.refreshAll()
```

**Modify:** `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`  
Same replacement as above.

**Modify:** `Wilgo/Features/Commitments/ListCommitmentView.swift`  
Replace existing `SlotStartNotificationScheduler.refresh()` in `deleteCommitments` with `CommitmentChangeRefresher.refreshAll()`.

**Tests:** No unit tests needed — this is pure delegation. Existing tests cover each scheduler independently.

---

### Phase 2 — Archive action on active list (depends on Commit 1)

#### Commit 3 — swipe-to-archive on ListCommitmentView #CommitmentArchive

**Depends on:** Commit 1, Commit 2

**Modify:** `Wilgo/Features/Commitments/ListCommitmentView.swift`

1. Change `@Query` predicate to filter active only:
```swift
@Query(filter: Commitment.activePredicate,
       sort: \Commitment.createdAt, order: .forward)
private var commitments: [Commitment]
```

2. Replace `.onDelete(perform: deleteCommitments)` with `.swipeActions(edge: .trailing)`:
```swift
.swipeActions(edge: .trailing) {
    Button {
        archiveCommitment(commitment)
    } label: {
        Label("Archive", systemImage: "archivebox")
    }
    .tint(.orange)
}
```

3. Replace `deleteCommitments` with `archiveCommitment`:
```swift
private func archiveCommitment(_ commitment: Commitment) {
    withAnimation {
        commitment.archivedAt = Date()
    }
    CommitmentChangeRefresher.refreshAll()
}
```

**Modify:** `Wilgo/Features/Stage/StageView.swift`  
Add predicate to `@Query`:
```swift
@Query(filter: Commitment.activePredicate,
       sort: \Commitment.createdAt, order: .forward)
private var commitments: [Commitment]
```

**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift` line 10  
Change:
```swift
@Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
```
to:
```swift
@Query(filter: Commitment.activePredicate,
       sort: \Commitment.createdAt, order: .forward)
private var commitments: [Commitment]
```
Archived commitments must not appear in cycle-end reports.

**Create:** `Shared/Models/Commitment+FetchDescriptor.swift`
```swift
import SwiftData

extension Commitment {
    /// Shared predicate for excluding archived commitments. Used by both
    /// `@Query` sites (which require an inline predicate value) and
    /// `FetchDescriptor.activeOnly` (for imperative fetches).
    static var activePredicate: Predicate<Commitment> {
        #Predicate<Commitment> { $0.archivedAt == nil }
    }
}

extension FetchDescriptor where T == Commitment {
    static var activeOnly: FetchDescriptor<Commitment> {
        FetchDescriptor<Commitment>(predicate: Commitment.activePredicate)
    }
}
```

**Modify:** `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` line 20  
**Modify:** `Wilgo/Features/Notifications/CatchUpReminder.swift` line 74  
**Modify:** `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` line 17  
**Modify:** `Wilgo/Features/Notifications/NowLiveActivityManager.swift` lines 25 & 133  
**Modify:** `Wilgo/Features/Settings/SettingsView.swift` line 65  
**Modify:** `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift` lines 77 & 90  
In each, replace `FetchDescriptor<Commitment>()` with:
```swift
.activeOnly
```

Note: `@Query` sites (`ListCommitmentView`, `StageView`, `FinishedCycleReportView`) cannot use the `FetchDescriptor.activeOnly` extension directly — `@Query`'s `filter:` parameter takes a `Predicate<Commitment>` value, not a `FetchDescriptor`. They instead use the shared `Commitment.activePredicate`:
```swift
@Query(filter: Commitment.activePredicate, ...)
```

**Tests:** `WilgoTests/Commitment/CommitmentArchiveTests.swift`  
Add:
- Archiving a commitment sets `archivedAt` to a non-nil date
- Archived commitment is excluded from `archivedAt == nil` predicate

---

### Phase 3 — Archived list screen (depends on Commit 1 & 2, parallel with Commit 3)

#### Commit 4 — ArchivedCommitmentsView #CommitmentArchive

**Depends on:** Commit 1, Commit 2

**Create:** `Wilgo/Features/Commitments/ArchivedCommitmentsView.swift`

- `@Query(filter: #Predicate { $0.archivedAt != nil }, sort: \Commitment.archivedAt, order: .reverse)`
- List with `insetGrouped` style
- Per-row swipe actions:
  - Trailing "Delete" (red, destructive) with confirmation alert before `modelContext.delete()` + `CommitmentChangeRefresher.refreshAll()`
  - Leading "Unarchive" (blue) — sets `archivedAt = nil`, re-anchors cycle via `commitment.cycle = Cycle.makeDefault(commitment.cycle.kind)`, calls `CommitmentChangeRefresher.refreshAll()`
- `EditButton` in toolbar for bulk unarchive
- Empty state: `ContentUnavailableView` with "No Archived Commitments" title and subtitle "Commitments you archive will appear here."
- Tap row → `CommitmentDetailView(commitment:, isArchived: true)` as sheet

**Tests:** `WilgoTests/Commitment/CommitmentArchiveTests.swift`  
Add:
- Unarchiving sets `archivedAt` back to `nil`
- Archived list query returns only commitments with non-nil `archivedAt`, sorted by `archivedAt` descending

---

### Phase 4 — Wire up entry point and detail view (depends on 3 & 4)

#### Commit 5 — NavigationLink entry point in ListCommitmentView #CommitmentArchive

**Depends on:** Commit 3, Commit 4

**Modify:** `Wilgo/Features/Commitments/ListCommitmentView.swift`  
Add a `Section` before the commitments `ForEach`:

```swift
Section {
    NavigationLink(destination: ArchivedCommitmentsView()) {
        Label("Archived", systemImage: "archivebox")
            .foregroundStyle(.secondary)
            .font(.subheadline)
    }
}
```

---

#### Commit 6 — hide configuration UI in CommitmentDetailView for archived commitments #CommitmentArchive

**Depends on:** Commit 4

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift`

1. Derive `isArchived` from the commitment:
```swift
private var isArchived: Bool { commitment.archivedAt != nil }
```

2. Conditionally hide Current cycle section:
```swift
if !isArchived { currentSection }
```

3. Conditionally hide Edit toolbar button:
```swift
if !isArchived {
    ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { onEdit?() }
    }
}
```

**Out of scope / unchanged for archived commitments:**
- `historySection` (heatmap, including the info card's backfill-add and delete-check-in actions) stays visible and interactive.
- `backfillButton` ("Backfill a Check-in") stays visible and interactive.
- `pastCyclesSection` ("Past Cycles" / `CycleRecord`s) stays visible.

These are all historical-data views/edits, not configuration, and remain available per the "history is the valuable part" principle.

**Tests:** No new unit tests — UI-only change. Manual verification: open an archived commitment detail, confirm Current cycle section and Edit are hidden, while History (heatmap + both backfill entry points + delete check-in) and Past Cycles remain visible and usable.

---

## Critical Files

| File | Role |
|---|---|
| `Shared/Models/Commitment.swift` | Model change — must land first |
| `Wilgo/Shared/CommitmentChangeRefresher.swift` (new) | Unified refresh — all mutation callers depend on this |
| `Wilgo/Features/Commitments/ArchivedCommitmentsView.swift` (new) | Archived list screen |
| `Wilgo/Features/Commitments/ListCommitmentView.swift` | Archive swipe + entry point |
| `Wilgo/Features/Stage/StageView.swift` | Filter out archived |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportView.swift` | Filter `@Query` out archived |
| `Wilgo/Features/Commitments/FinishedCycleReport/FinishedCycleReportModifier.swift` | Filter both fetches |
| `Shared/Models/Commitment+FetchDescriptor.swift` (new) | `FetchDescriptor.activeOnly` extension |
| `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | Filter fetch |
| `Wilgo/Features/Notifications/CatchUpReminder.swift` | Filter fetch |
| `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` | Filter fetch |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift` | Filter both fetches |
| `Wilgo/Features/Settings/SettingsView.swift` | Filter week-start fetch |
| `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift` | Read-only archived detail |

### Dependency Graph

```
Commit 1: add archivedAt to Commitment
Commit 2: extract CommitmentChangeRefresher      [parallel with Commit 1]
    |
    +-- Commit 3: swipe-to-archive on active list  [after 1 & 2]
    +-- Commit 4: ArchivedCommitmentsView           [after 1 & 2, parallel with 3]
            |
            +-- Commit 5: NavigationLink entry point  [after 3 & 4]
            +-- Commit 6: read-only detail view        [after 4, parallel with 5]
```
