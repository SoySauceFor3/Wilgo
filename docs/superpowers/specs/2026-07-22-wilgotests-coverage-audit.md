# WilgoTests Coverage Audit — Stage 4 Report

## Metadata

- **Author:** Claude (with 3Sauce)
- **Date:** 2026-07-23
- **Parent design:** [2026-07-22-wilgotests-cleanup-design.md](./2026-07-22-wilgotests-cleanup-design.md) — Stage 4
- **Tracking:** https://app.notion.com/p/clean-up-tests-3904b58e32c38021a045ef05dd44318a?source=copy_link
- **Scope:** Report only. **No tests written.** 3Sauce reviews and decides what (if anything) to add.

## Method

Cross-referenced every source `.swift` under `Shared/`, `Wilgo/`, `WidgetExtension/` against the
reorganized `WilgoTests/` tree. Each "no coverage" call was verified by (a) locating the subject's
defining symbol and (b) confirming no test file exercises it — not merely by name-matching, since some
subjects are tested behaviorally under a differently-named file. Files whose only content is SwiftUI
view rendering (no extractable logic) are classified separately from files with genuine untested logic.

## Legend

- ✅ **Covered** — a dedicated test file exercises the subject's logic.
- ⚠️ **Gap (logic)** — file contains extractable, testable logic that has **no** test. Actionable.
- 🎨 **View-only** — pure SwiftUI rendering / wiring; no unit-testable logic. Low value to unit-test
  (would need snapshot/UI tests, out of scope for this suite).
- 🔌 **Side-effect orchestration** — ActivityKit / BGTask / system-framework glue; unit-testing gives
  little value without heavy mocking. Judgment call, generally leave uncovered.

---

## Priority 1 — Real logic, no coverage (recommend adding tests)

These have branching logic, pure functions, or state machines and would be cheap and valuable to test.

| Source | Untested logic | Notes |
|---|---|---|
| `Wilgo/Features/Commitments/CheckInUndo/CheckInUndoManager.swift` | `enqueue`, `undo`, `dismissAll`, `autoDismiss`, `removeNotice` | An `ObservableObject` state machine managing a queue of undo notices with auto-dismiss timing. Pure in-memory logic — highly testable, currently 0 tests. **Highest-value gap.** |
| `Wilgo/Features/PositivityToken/PTBadgeState.swift` | `update(currentCapacity:)`, `hasNewCapacity`, `markAsSeen`, `capacitySeenByUser` | `@Observable` badge state with "new capacity seen" logic. Small, pure, easy to test. |
| `Shared/Models/Commitment+FetchDescriptor.swift` | `activePredicate`, `activeOnly` | The active-commitment `Predicate`/`FetchDescriptor`. Testable against an in-memory container (insert active + archived, assert the fetch filters correctly). |
| `Wilgo/WilgoApp.swift` → deep-link parser | `handleDeepLink(_:)` + inner `queryValue(_:)` | URL-scheme parsing is pure string logic embedded in the `App`. See "Catch-all" below — extract it and test the parse. |

## Priority 2 — Logic, low-to-moderate value or awkward to isolate

| Source | Status | Notes |
|---|---|---|
| `Wilgo/Features/LiveUpdates/RefreshCoordination/CommitmentChangeRefresher.swift` | ⚠️ thin | Single `static func refreshAll() async` that fans out to other (tested) refreshers. Little branching of its own; a test would mostly assert delegation. Low priority. |
| `Wilgo/Features/Stage/Current.swift` → `snoozeCurrentSlot()` | ⚠️ buried in view | Snooze action logic lives inside `CurrentCommitmentRow`. The underlying snooze model is covered (`SlotOccurrenceSnoozeTests`); the view-level wiring is not extractable without refactor. |
| `Wilgo/Features/PositivityToken/AddView.swift` → `saveToken()` | ⚠️ buried in view | Token-creation persistence path inside the view. Model minting is covered by `PositivityTokenModelTests`; this specific save wiring is not. |
| `Wilgo/Features/PositivityToken/ListView.swift` → `deleteTokens(in:offsets:)` | ⚠️ buried in view | Delete-by-section-offset logic. Grouping is covered (`PositivityTokenGroupingTests`); the offset→delete mapping is not. |

## Priority 3 — Side-effect orchestration (recommend leaving uncovered)

Heavy on ActivityKit / BGTask / system frameworks. Unit tests would be mostly mock-assertion with low
defect-catching value. Their pure inputs are already tested elsewhere.

| Source | Why skip | Pure logic that IS covered |
|---|---|---|
| `Wilgo/Features/LiveUpdates/Schedulers/NowLiveActivity/LiveActivityRefresher.swift` | ActivityKit `Activity<>` request/update/end orchestration | Planning inputs covered by `LiveActivityPlannerTests` |
| `Wilgo/Features/LiveUpdates/Schedulers/NowLiveActivity/NowLiveActivityManager.swift` | `performWork()` BGTask entry glue | Delegates to the (covered) planner/refresher |
| `Wilgo/Features/LiveUpdates/Infrastructure/BGWake.swift` | BGTask registration — but note it **does** have `BGWakeTests` for the testable parts | partially covered |

## View-only files (no unit-testable logic — out of scope)

Pure SwiftUI rendering / navigation wiring. Would require snapshot or UI tests (not this suite's remit).
Listed for completeness so the gap is a deliberate decision, not an oversight.

- Commitments views: `ArchivedCommitmentsView`, `ListCommitmentView`, `CommitmentDetailView`,
  `CommitmentRowView`, `CommitmentStatsCard`, `SlotView`, `Backfill/BackfillSheet`,
  `CheckInUndo/CheckInUndoBannerOverlay`, `Form/AddCommitmentView`, `Form/EditCommitmentView`,
  `Form/CommitmentFormFields`
- FinishedCycleReport views: `FCRCycleCardView`, `FinishedCycleReportView`,
  `FinishedCycleReportModifier`, `Models.swift` (plain data types)
- Heatmap: `Heatmap/View.swift`, `Heatmap/HeatmapNamespace.swift`, `Heatmap/InfoCardView.swift`
  (note: derivation logic in `InfoCardView` static funcs **is** covered by `InfoCardDerivationTests`)
- Stage views: `Stage/CatchUp.swift`, `Stage/Upcoming.swift`, `Stage/StageView.swift`
- PositivityToken views: `PTBadgeObserver.swift`
- Tags views: `TagFilterChipsView`, `TagPickerSection`, `TagsSettingsView`
- Root: `MainTabView`, `Settings/SettingsView` (see catch-all below)
- Widget targets: `WidgetExtension/CurrentCommitmentWidget.swift`, `WidgetExtension/NowLiveActivity.swift`,
  `WidgetExtension/WidgetBundle.swift`

## Dead / stub test files (cleanup candidates)

- `WilgoTests/Shared/Models/PositivityToken/PositivityTokenMintingTests.swift` — an empty
  `struct PositivityTokenMintingTests {}` with a comment noting minting was removed in commit 2A.
  Carries no assertions. **Recommend deleting** (its historical note could move to a comment in
  `PositivityTokenModelTests` if worth keeping).

---

## Catch-all source files — future-split candidates

Per the design's Stage 4 mandate to flag catch-all files mixing many testable subjects:

### `Wilgo/WilgoApp.swift` (169 lines)
Mixes at least five distinct concerns in one file:
1. `sharedModelContainer` construction
2. `refreshCoordinator` lifecycle
3. `handleDeepLink` + `queryValue` — **pure URL parsing, testable, should be extracted**
4. `BackgroundAssertion` (begin/end) — a small testable helper class
5. `DeepLinkedDetailView` / `AppRootView` — view wiring

**Recommendation:** Extract the deep-link parsing into its own `DeepLinkRouter` (or similar) type in a
dedicated file, then it becomes trivially unit-testable (Priority 1 above). `BackgroundAssertion` could
likewise move out. This both improves testability and slims the `App` entry point.

### `Wilgo/Features/Settings/SettingsView.swift` (296 lines)
Holds 8 distinct `@AppStorage`-backed settings plus helpers `applyWeekStartChange()` and `hourLabel(_:)`.
The settings *values* are covered by `AppSettings*` tests, and `WeekStartChangeHandler` (which this view
calls) is covered by `WeekStartChangeHandlerTests`. What's left in the view is presentation wiring.

**Recommendation:** No test gap that isn't already better served at the `AppSettings`/handler layer.
A future split (e.g. separating the notification-toggles section and the debug section into subviews)
would improve readability but yields little new *testable* surface. Lower priority than `WilgoApp.swift`.

---

## Summary

- **Well-covered:** all `Shared/Models`, `Shared/Scheduling`, `Shared/Widget` intents, `AppSettings`,
  the entire `FinishedCycleReport` builder layer, LiveUpdates schedulers' pure planners, Heatmap
  derivation, Tags/Settings handlers. The reorganized tree makes this coverage easy to see.
- **Top 4 actionable gaps (Priority 1):** `CheckInUndoManager`, `PTBadgeState`,
  `Commitment+FetchDescriptor`, and the extracted-`WilgoApp` deep-link parser.
- **One dead stub** to delete: `PositivityTokenMintingTests.swift`.
- **Two catch-all files** worth a future split for testability: `WilgoApp.swift` (higher value),
  `SettingsView.swift` (lower value).

No behavior changed; no tests added. Awaiting 3Sauce's decision on which gaps to close.
