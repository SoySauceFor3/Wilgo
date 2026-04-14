# Check-In Deletion

**Notion:** https://www.notion.so/Allow-checkIn-deletion-not-just-during-undo-banner-33b4b58e32c380ed9564c29da5af2c79

**Tag:** `#CheckInDeletion`

---

## PRD

### Problem

The existing undo banner only appears when a check-in is created inside the app (5-second window). Check-ins made via the interactive widget or Live Activity (lock screen) bypass the app entirely — no banner is shown, so accidental taps have no recovery path.

### Goal

Allow users to delete any check-in at any time, surfaced naturally within the existing heatmap flow.

### Expected Behavior

1. User taps a heatmap tile → info card appears (existing behavior).
2. Info card now shows each check-in as its own row, with:
   - Timestamp
   - Source label (if applicable): **"widget"**, **"lock screen"**, or **"backfilled"**. Normal in-app check-ins show no label.
   - A **−** (minus) button on the right.
3. **Mis-tap protection:** tapping − puts the row into a pending-delete state (row highlights red, button label changes to "Confirm") for **1 second**. A second tap within that window confirms deletion. If no second tap, the row resets to normal.
4. An **"Add check-in"** button at the bottom of the info card opens `BackfillSheet` pre-constrained to the selected tile's date range.
5. Deleting a check-in immediately updates the heatmap cell color and stats (SwiftData change propagation).

### UI Mockup

Mockup HTML saved at:
`.superpowers/brainstorm/84369-1776149847/content/infocard-delete.html`
→ Option **A** (inline delete rows) was selected.

### Out of Scope

- Bulk deletion
- Undo after deletion (the action is already two-tap confirmed)
- Changing a check-in's timestamp after creation

---

## Implementation Plan

### Summary

Add a `source` field to `CheckIn` (SwiftData migration), thread the source through all creation call sites, then augment `CommitmentHeatmapInfoCard` to render per-row delete UI and an "Add check-in" shortcut.

### Model Change

**`CheckIn.swift`** — add `source: CheckInSource` with default `.app`.

```swift
enum CheckInSource: String, Codable {
    case app          // normal in-app tap — no label shown
    case widget       // interactive widget button
    case liveActivity // Live Activity / lock screen button
    case backfill     // BackfillSheet
}
```

SwiftData will handle the migration automatically via the default value (`.app` for all existing records).

### Major Alternatives Considered

| Option | Decision |
|---|---|
| Source label only on widget/LA check-ins | ✅ Chosen — less noise |
| Source label on all check-ins (including `.app`) | Rejected — redundant for the normal case |
| Swipe-to-delete (Option B) | Rejected — gesture conflicts with horizontal heatmap scroll; less discoverable |
| Separate "Check-in History" view | Rejected — heatmap tile tap already scopes to a period, no new nav needed |

---

## Commit Plan

Dependencies: Commits 1–3 are independent of each other but all must land before Commit 4.

---

### Commit 1 — `#CheckInDeletion` Add `CheckInSource` enum + `source` field to `CheckIn` model

**Files:** `Shared/Models/CheckIn.swift`

- Add `CheckInSource` enum (`app`, `widget`, `liveActivity`, `backfill`)
- Add `var source: CheckInSource = .app` to `CheckIn`
- Update `CheckIn.init` to accept `source: CheckInSource = .app`

**Tests:** Unit test that a `CheckIn` inserted without a source defaults to `.app`; test that each source value round-trips through `Codable`.

**Note:** SwiftData lightweight migration — no migration plan needed, default value covers existing records.

---

### Commit 2 — `#CheckInDeletion` Thread `source` through all check-in creation call sites

**Depends on:** Commit 1

**Files:**
- `WidgetExtension/CheckInIntent.swift` — add `source` parameter to `CheckInIntent`; add `var sourceRaw: String` parameter (`.widget`)
- `WidgetExtension/NowLiveActivity.swift` — pass `source: .liveActivity` to `CheckInIntent`; widget button passes `source: .widget`
- `Wilgo/Features/Commitments/Backfill/BackfillSheet.swift` — pass `source: .backfill` to `CheckIn` init
- All other in-app check-in creation sites — pass `source: .app` (or rely on default)

**Note:** `CheckInIntent` communicates across process boundaries — `source` must be encoded as a `String` parameter and decoded inside `perform()`.

**Manual verification:** After this commit, tap the widget → verify the new check-in has `source == .widget` in a debug print or test. Tap from Live Activity → verify `.liveActivity`.

**Tests:** Unit test `CheckInIntent.perform()` with `sourceRaw = "widget"` produces a `CheckIn` with `.widget`; same for `liveActivity`.

---

### Commit 3 — `#CheckInDeletion` Augment `CommitmentHeatmapInfoCard` with per-row delete UI + pending-delete state

**Depends on:** Commit 1

**Files:** `Wilgo/Features/Commitments/SingleCommitment/Heatmap/InfoCardView.swift`

Changes:
- Replace the joined timestamp string with a `ForEach` over `period.checkIns`, each row showing:
  - Timestamp (`createdAt` formatted as time)
  - Source label (if not `.app`): "widget", "lock screen", "backfilled"
  - `−` button on the right
- `@State private var pendingDeleteID: UUID? = nil` — tracks which row is in confirm-pending state
- Tapping `−`: sets `pendingDeleteID = checkIn.id`, schedules a 1-second `Task` that clears it if not confirmed
- While pending: row background turns red, button shows "Confirm"
- Second tap while pending: calls `onDelete(checkIn)`
- `onDelete: (CheckIn) -> Void` callback passed in from `CommitmentHeatmapView`

**Tests:** Unit test the pending-delete state machine: tap once → pending; tap again within 1s → `onDelete` called; tap once → wait 1s → state resets.

---

### Commit 4 — `#CheckInDeletion` Wire delete + backfill-from-tile into `CommitmentHeatmapView`

**Depends on:** Commits 2 + 3

**Files:**
- `Wilgo/Features/Commitments/SingleCommitment/Heatmap/View.swift`
- `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift`

Changes in `CommitmentHeatmapView`:
- Pass `onDelete` closure to `CommitmentHeatmapInfoCard`:
  ```swift
  modelContext.delete(checkIn)
  WidgetCenter.shared.reloadTimelines(...)
  ```
- Add `@State private var backfillPeriod: Heatmap.PeriodData? = nil`
- `CommitmentHeatmapInfoCard` gets an `onAddCheckIn: () -> Void` callback
- "Add check-in" button in the card calls `onAddCheckIn` → sets `backfillPeriod = selectedPeriod`
- `.sheet(item: $backfillPeriod)` presents `BackfillSheet` with `dateRange` derived from the period's `periodStartPsychDay...periodEndPsychDay`

**Tests:**
- Integration test: insert a `CheckIn`, render `CommitmentHeatmapView`, trigger delete → verify `CheckIn` is removed from context.
- Integration test: tap "Add check-in" on a daily tile → verify `BackfillSheet` opens with the correct date range.

**Manual verification:** Open the app, tap a heatmap tile with multiple check-ins, delete one, confirm heatmap cell color updates correctly.
