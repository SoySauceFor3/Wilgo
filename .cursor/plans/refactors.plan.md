---
name: ""
overview: ""
todos: []
isProject: false
---

# Codebase Refactor & Performance Suggestions

Scan date: 2026-04-01  
Status legend: ✅ Done · 🔲 Pending

---

## ✅ 1 — StageViewModel: cache Stage derivations (HIGH)

**Problem**  
`StageView.body` recomputed three expensive lists on every evaluation:

```swift
// BEFORE – ran on every body call
let current  = CommitmentAndSlot.currentWithBehind(commitments: commitments, now: now)
let upcoming = CommitmentAndSlot.upcomingWithBehind(commitments: commitments, after: now)
let catchUp  = CommitmentAndSlot.catchUpWithBehind(commitments: commitments, now: now)
```

Each helper iterates all commitments and calls `Commitment.stageStatus`, which itself runs a nested day × slot loop over the full cycle window.  
Additionally, all three `CommitmentRow` types called `commitment.stageStatus(now:)` again in their own `body` just to read `behindCount`.

**Fix applied**

- Created `Wilgo/Features/Stage/StageViewModel.swift` (`@MainActor @Observable`).
  - `refresh(commitments:)` — called by `StageView` via `.onChange` / scenePhase; recomputes once and stores results.
  - Internal `Task` timer wakes at the next slot-boundary transition (same logic as the old `rewrite` toggle + `.task(id: rewrite)` sleep loop, now isolated to the view model).
- `StageView` now reads `viewModel.current/upcoming/catchUp` — no in-body computation.
- Removed the `rewrite: Bool` state toggle and `.task(id: rewrite)` block.
- `CurrentCommitmentRow`, `CatchUpCommitmentRow`, `UpcomingCommitmentRow` now accept a pre-computed `behindCount: Int` parameter; their `body` no longer calls `stageStatus`.

**Files changed**  
`Features/Stage/StageViewModel.swift` (new)  
`Features/Stage/StageView.swift`  
`Features/Stage/Current.swift`  
`Features/Stage/CatchUp.swift`  
`Features/Stage/Upcoming.swift`

---

## 🔲 2 — Extract shared CommitmentRowContainer (HIGH)

**Problem**  
`CurrentCommitmentRow`, `CatchUpCommitmentRow`, and `UpcomingCommitmentRow` each duplicate:

- `@State private var isPresentingDetail = false`
- `@State private var isPresentingEdit = false`
- `.contentShape(Rectangle()).onTapGesture { isPresentingDetail = true }`
- `.sheet(isPresented: $isPresentingDetail) { CommitmentDetailView(...) ... }`
- `.fullScreenCover(isPresented: $isPresentingEdit) { NavigationStack { EditCommitmentView(...) } }`

**Suggested fix**  
Extract a `CommitmentRowShell` view modifier or wrapper view that owns the two `@State` booleans and wires the sheet / full-screen cover. The three row types become the content passed into it:

```swift
struct CommitmentRowShell<Content: View>: View {
    let commitment: Commitment
    @ViewBuilder let content: () -> Content
    @State private var isPresentingDetail = false
    @State private var isPresentingEdit   = false
    // …sheet + fullScreenCover here
}
```

**Files to change**  
`Features/Stage/Current.swift`, `CatchUp.swift`, `Upcoming.swift`

---

## 🔲 3 — Cache DateFormatter instances (MEDIUM)

**Problem**  
`DateFormatter()` is allocated per-call in several hot rendering paths:

| Location                            | Call site                          |
| ----------------------------------- | ---------------------------------- |
| `Heatmap/View.swift` ~416, ~593–624 | `periodColumnLabel`, `periodLabel` |
| `CommitmentDetailView.swift` ~153   | `formattedShortDate`               |
| `Time.swift` ~76–81                 | `timeString`                       |

SwiftUI views re-evaluate frequently; each allocation is cheap on its own but adds up across cells and refreshes.

**Suggested fix**  
Replace with `static let` cached formatters or SwiftUI `FormatStyle`:

```swift
// BEFORE
let formatter = DateFormatter()
formatter.dateFormat = "MMM d"
return formatter.string(from: date)

// AFTER
private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()
```

**Files to change**  
`Heatmap/View.swift`, `CommitmentDetailView.swift`, `Time.swift`

---

## 🔲 4 — Cache heatmap period builders (MEDIUM)

**Problem**  
`CommitmentHeatmapView` calls `dailyPeriods()` / `weeklyPeriods()` / `monthlyPeriods()` (each building ~180-day windows) from computed view branches on every refresh.  
`Heatmap/Data.swift` ~92–135 rebuilds these arrays unconditionally.

**Suggested fix**  
Introduce a `HeatmapViewModel` (or extend the existing `Data` type) that caches `PeriodData` arrays keyed by `(commitment.persistentModelID, heatmapKind)` and invalidates only when the commitment's checkIns change:

```swift
private var cache: [HeatmapCacheKey: [PeriodData]] = [:]
```

**Files to change**  
`Heatmap/View.swift`, `Heatmap/Data.swift`

---

## 🔲 5 — Fix misleading CatchUpReminder API parameter (HIGH)

**Problem**  
`CatchUpReminder.nextNotificationDate(lastNewCatchUpCommitmentDate:)` declares a `Date` parameter but the body ignores it entirely — only `UserDefaults` is read. The parameter name is misleading and the passed value is always discarded.

`CatchUpReminder.swift` ~98–120

**Suggested fix**  
Either remove the parameter and make the intent clear with a `UserDefaults`-only signature, or actually use the parameter value in the scheduling logic as originally intended.

---

## 🔲 6 — Scope TimelineView to mint countdown banner only (MEDIUM)

**Problem**  
`ListPositivityTokenView` wraps the entire `NavigationStack` in `TimelineView(.periodic(from:by: 60))`, causing the full navigation stack to re-evaluate every minute just to update a small mint countdown banner.

`Features/PositivityToken/ListView.swift` ~11–80

**Suggested fix**  
Move `TimelineView` to wrap only the banner component:

```swift
TimelineView(.periodic(from: .now, by: 60)) { _ in
    MintCountdownBanner(...)
}
```

---

## 🔲 7 — Replace UIApplication screen-width lookup with GeometryReader (MEDIUM)

**Problem**  
`CommitmentStatsCard` reads `DisplayInfo.width` on every layout, which hits the UIKit window scene directly (`UIApplication.shared.connectedScenes`…).

`Features/Commitments/SingleCommitment/CommitmentStatsCard.swift` ~57–60

**Suggested fix**  
Pass width via `GeometryReader` or read it from the SwiftUI environment using `\.horizontalSizeClass` / `containerRelativeFrame`.

---

## 🔲 8 — Deduplicate PersistentIdentifier encode/decode (MEDIUM)

**Problem**  
The same JSON/base64 encode-decode pattern for `PersistentIdentifier` appears in two places:

| File                       | Lines    |
| -------------------------- | -------- |
| `WilgoApp.swift`           | ~8–17    |
| `CheckInUndoManager.swift` | ~114–117 |

**Suggested fix**  
Extract a single `extension PersistentIdentifier` with `encoded() -> String` and `init?(encoded:)` methods. `WilgoApp` already has `encoded()` defined on it; move it to a shared file.

---

## 🔲 9 — Remove dead code (LOW)

| Item                                                                                                            | Location                                                 |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `DayStartReport.swift` — marked for deletion at top of file                                                     | `Features/Notifications/DayStartReport.swift`            |
| `CommitmentFormFields.allowedSkipBudgetCycleKinds` — defined but never referenced                               | `Features/Commitments/CommitmentFormFields.swift` ~78–91 |
| `MiniCommitmentHeatmapRow.completionsByDay` — declared but never used                                           | `Heatmap/View.swift` ~643–668                            |
| `DayStartReport.summaryNotificationContent` urgency sort — comparator always returns `0`/`0`, sort does nothing | `DayStartReport.swift` ~99–107                           |

---

## 🔲 10 — Tighten SwiftData concurrency (HIGH)

**Problem**  
`CatchUpReminder.startHourlyRunWhileActive` uses `Task.detached` to access SwiftData models without a clear actor context. `DayStartReport` and deep-link handlers create `ModelContext(WilgoApp.sharedModelContainer)` from arbitrary callers.

`Features/Notifications/CatchUpReminder.swift` ~11–17  
`Features/Notifications/DayStartReport.swift` ~40–42

**Suggested fix**  
Document and enforce a threading contract: contexts created from `sharedModelContainer` should always be used on `@MainActor`, or explicitly create background contexts with `ModelContext(container, concurrencyType: .privateQueue)` (or equivalent) and annotate accordingly.

---

## 🔲 11 — Replace fatalError with non-fatal fallbacks (HIGH)

**Problem**  
Two hard crashes in production paths:

| Location                | Trigger                                 |
| ----------------------- | --------------------------------------- |
| `WilgoApp.swift` ~33–37 | `ModelContainer` init failure           |
| `Time.swift` ~68–71     | `Calendar.dateComponents` returning nil |

**Suggested fix**

- `WilgoApp`: show a user-visible error state instead of crashing.
- `Time.psychDay`: return `Date()` as a safe fallback and log the anomaly.

---

## 🔲 12 — Preview factory consolidation (LOW)

**Problem**  
`StagePreviewFactory`, `ListCommitmentView` preview, and `HeatmapPreviewFactory` each repeat the same `ModelContainer(for: Commitment.self, Slot.self, CheckIn.self, configurations: .init(isStoredInMemoryOnly: true))` setup and sample commitment construction.

**Suggested fix**  
Extract a single `PreviewContainer.swift` helper under `Wilgo/Shared/` with factory methods for common model combinations.

`Features/Stage/StageView.swift` ~143–235  
`Features/Commitments/ListCommitmentView.swift` ~65–121  
`Heatmap/View.swift` ~692–766
