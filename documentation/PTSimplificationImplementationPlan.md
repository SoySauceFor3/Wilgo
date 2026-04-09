# PT Simplification — Implementation Plan

> **PRD:** [PT Simplification PRD](https://www.notion.so/PT-Simplification-33b4b58e32c380d3b924f6bb82a403ee?source=copy_link)  
> **Tracking:** also in [PT Simplification PRD](https://www.notion.so/PT-Simplification-33b4b58e32c380d3b924f6bb82a403ee?source=copy_link)
> **Decision:** Option A (mint-time capacity constraint)  
> **Date:** 2026-04-08

---

## Summary / Architecture

Replace the "1-hour window after check-in" minting model with a **capacity-based** model:

- User may mint a PT only when `totalPTCreated < totalCheckIns` (lifetime counts).
- PT is **not** linked to any specific check-in. Undoing a check-in never deletes a PT.
- Monthly usage budget and FIFO compensation in `FinishedCycleReport` are **unchanged**.
- The PT list view gains a persistent summary header (Created / Used / Active / Monthly budget remaining) and capacity-aware mint gating.

---

## Model Changes

### `PositivityToken` (`Shared/Models/PositivityToken.swift`)


| Change                              | Detail                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| Remove `@Relationship` to `CheckIn` | Delete the `var checkIn: CheckIn?` property and its `@Relationship` decorator. |
| Remove `checkIn` from `init`        | New signature: `init(reason: String, createdAt: Date = .now)`                  |


### `CheckIn` (`Shared/Models/CheckIn.swift`)


| Change                                         | Detail                                                 |
| ---------------------------------------------- | ------------------------------------------------------ |
| Remove `var positivityToken: PositivityToken?` | Inverse of the removed relationship — delete entirely. |


### SwiftData migration

Dropping an optional `@Relationship` between two models is typically handled by **lightweight migration** (SwiftData auto-detects removed properties). The app uses a **shared App Group store** (main app + widget), so we must verify on a device/simulator with an existing store before release.

**If the store fails to open:** introduce `VersionedSchema` + `SchemaMigrationPlan` (v1 = current, v2 = without the relationship) and a nil-out migration stage. Document the exact error in a PR comment.

---

## Logic Changes

### `PositivityTokenMinting.swift` — full rewrite

Replace the time-window helpers with capacity-based helpers:

```swift
// New API (replaces all existing public functions)
static func mintCapacity(tokenCount: Int, checkInCount: Int) -> Int {
    max(0, checkInCount - tokenCount)
}

static func canMint(tokenCount: Int, checkInCount: Int) -> Bool {
    mintCapacity(tokenCount: tokenCount, checkInCount: checkInCount) > 0
}

// Count helpers (query callers pass the values)
static func fetchTotalTokenCount(context: ModelContext) throws -> Int
static func fetchTotalCheckInCount(context: ModelContext) throws -> Int
```

Remove: `windowAfterCheckIn`, `isCheckInSponsorable`, `eligibleCheckIn`, `secondsRemainingInMintWindow`, `recentCheckInsLowerBound`, `fetchRecentCheckInsForMint`.

---

## UI Changes

### `AddPositivityTokenView` (`Features/PositivityToken/AddView.swift`)

- Remove `sponsoringCheckIn: CheckIn` parameter entirely.
- Remove `onReceive(.CheckInRevoked)` handler (no longer relevant — no sponsoring check-in).
- Remove `checkInUndoManager.dismissAll()` call on appear (was only needed to prevent undo of the sponsoring check-in while the sheet was open).
- `saveToken()` becomes: `PositivityToken(reason: trimmedReason)` — no checkIn arg.

### `ListPositivityTokenView` (`Features/PositivityToken/ListView.swift`)

- Remove `@State private var sponsoringCheckIn: CheckIn?`, all polling tasks, and `onReceive(.CheckInRevoked)`.
- Remove `MintWindowBanner` (and its `TimelineView` wrapper) entirely.
- **Add a persistent summary section** at the top (always visible):

  | Row                      | Value                                                                   |
  | ------------------------ | ----------------------------------------------------------------------- |
  | Created                  | `tokens.count`                                                          |
  | Used                     | `tokens.filter { $0.status == .used }.count`                            |
  | Active                   | `tokens.filter { $0.status == .active }.count`                          |
  | Monthly budget remaining | derived from `PositivityTokenCompensator` monthly cap logic (see below) |

- **Mint capacity row** below the summary:
  - When `capacity > 0`: show capacity number (e.g. "2 mints available").
  - When `capacity == 0`: show disabled state copy: *"Create more check-ins to mint more PTs."*
- Toolbar `+` button: enabled when `capacity > 0`, disabled otherwise.
- Sheet: present `AddPositivityTokenView()` (no sponsoring check-in arg).

**Monthly budget remaining helper** — add a small pure function (or computed var) that replicates the existing logic in `AfterPositivityTokenReportBuilder.positivityTokenMonthlyCap()` and counts tokens used this calendar month:

```swift
private func monthlyBudgetRemaining(tokens: [PositivityToken], cap: Int) -> Int {
    let usedThisMonth = tokens.filter { token in
        token.status == .used &&
        Calendar.current.isDate(token.dayOfStatus ?? .distantPast, equalTo: .now, toGranularity: .month)
    }.count
    return max(0, cap - usedThisMonth)
}
```

### `MainTabView` (`Features/Root/MainTabView.swift`)

- Replace the `@Query` for `sponsorableCheckIns` (time-window filter) with two `@Query`s:
  - `@Query private var allTokens: [PositivityToken]`
  - `@Query private var allCheckIns: [CheckIn]`
- Badge logic: `.badge(mintCapacity > 0 ? 1 : 0)` — a red dot (count = 1 produces a dot-style badge on iOS); set to `0` to hide.
  ```swift
  private var mintCapacity: Int {
      PositivityTokenMinting.mintCapacity(tokenCount: allTokens.count, checkInCount: allCheckIns.count)
  }
  ```
- Remove `mintBadgeClock`, `sponsorableCheckInsQuerySignature`, and the `onChange` timer that drove them — no longer needed since capacity updates reactively with model changes.

### Undo handlers — remove PT deletion branches

Three call sites enqueue check-in undo closures that also delete the linked PT. Remove only the `if let token = checkIn.positivityToken { context.delete(token) }` branches (keep `context.delete(checkIn)`):


| File                        | Location                                             |
| --------------------------- | ---------------------------------------------------- |
| `WilgoApp.swift`            | `handleDeepLink` → `"done"` case                     |
| `BackfillSheet.swift`       | undo closure inside `commitBackfill()` or equivalent |
| `CommitmentStatsCard.swift` | undo closure inside the Done button action           |


### Widget Extension schema

No change required — `PositivityToken.self` stays in the schema list. The widget only reads the store; removing the CheckIn relationship from the model is schema-compatible and the widget doesn't reference that property.

---

## FinishedCycleReport — "Exact reasons" copy

PRD asks for: *"Missing this commitment is compensated by your Positivity Tokens: {reason1}, {reason2}…"*

### Current state

`PositivityTokenCompensator.apply(...)` returns `[String: Int]` (cycleID → count). It mutates each token in-place (`token.status = .used`) but does **not** return which token objects were consumed, so the reasons are lost by the time `PositivityTokenPage` receives the report.

### Design

**Option 1 — Return consumed tokens alongside the count map**
Change `PositivityTokenCompensator.apply` to also return `[String: [PositivityToken]]` (cycleID → ordered consumed tokens). Caller extracts `.reason` from each.

Option 2 — Add a `consumedReasons: [String]` field to `CycleReport`
Thread the reasons directly through the report model. `AfterPositivityTokenReportBuilder`builds`CycleReport`with a populated`consumedReasons` list.

**Decision: Option 2.** Keeps the report model self-contained; callers never need raw token objects in the UI layer. The reasons are already strings; no extra model dependency leaks into `PositivityTokenPage`.

### Changes

#### `PositivityTokenCompensator` (`FinishedCycleReport/PositivityTokenCompensator.swift`)

Change the return type of `apply(cycleNeeds:tokens:monthlyCap:calendar:)` to `[String: [String]]` (cycleID → ordered consumed reasons, oldest-first FIFO order). The internal loop appends `token.reason` to the array instead of incrementing an int counter.

#### `Models.swift` (`FinishedCycleReport/Models.swift`)

Add field to `CycleReport`:

```swift
let consumedPTReasons: [String]   // empty when aidedByPositivityTokenCount == 0
```

Derive `aidedByPositivityTokenCount` from `consumedPTReasons.count` (remove as a stored field).

#### `AfterPositivityTokenReportBuilder`

Map the new `[String: [String]]` result into each `CycleReport`:

```swift
CycleReport(
    ...
    consumedPTReasons: reasonsByCycleID[cycle.id, default: []],
    ...
)
```

#### `PositivityTokenPage` (`FinishedCycleReport/PositivityTokenPage.swift`)

In `CycleResultRow`, when `cycle.isAidedByPositivityToken`, replace:

> *"Aided by N positivity token(s)"*

with PRD copy:

> *"Missing this commitment is compensated by your Positivity Tokens: {reason1}, {reason2}…"*

Render as a `Text` view, always expanded (no collapse/expand — no PRD spec for it).

### Testing additions

- Unit test: compensator returns reasons in FIFO order matching which tokens were consumed.
- Unit test: `consumedPTReasons` is empty for unaided and grace cycles.

---

## Reminders / Notifications

Per PRD "Reminders" section. Items 1–3 are in scope here; items 4–5 are explicitly "later / maybe" in the PRD and deferred.

### PRD items in scope

1. Push notification when capacity increases above 0 — *"Check-in on [commitment] unlocks a Positivity Token slot, come mint one."* Deep-links to PT page.
2. Encouragement copy in PT list when capacity > 0.
3. Red dot on Main Tab PT icon between capacity increase and first PT page open.

### Design

#### Notification delivery — follow `CatchUpReminder` pattern

Add a `**PositivityTokenReminder` enum (same shape as `CatchUpReminder`) with:

- Its own BGTask identifier: `"wilgo.pt-capacity-reminder"`.
- An `InAppScheduler` for hourly in-app polling.
- Called from the same two hooks in `WilgoApp`: `scenePhase` transitions + hourly scheduler.

#### Capacity-change detection via UserDefaults watermark


| Key                                     | Value                                            |
| --------------------------------------- | ------------------------------------------------ |
| `"PTReminder.lastKnownCheckInCount"`    | `Int` — total check-ins last evaluated           |
| `"PTReminder.capacityBecamePositiveAt"` | `Date?` — when capacity first crossed 0 → >0     |
| `"PTReminder.notificationSentAt"`       | `Date?` — prevents re-firing for the same window |


**Evaluation logic (runs ~hourly):**

```
fetch totalCheckInCount, totalPTCreated
capacity = max(0, totalCheckInCount - totalPTCreated)

if capacity > 0 AND capacityBecamePositiveAt == nil:
    set capacityBecamePositiveAt = now
    set unseenCapacity = true
    schedule push notification (fire ~1 min out)

if capacity == 0:
    clear capacityBecamePositiveAt
    cancel pending notification
```

#### "Seen" flag for tab red dot (PRD item 3)

The current badge (`mintCapacity > 0 ? 1 : 0`) clears only when PTs are minted. Per PRD, it should clear when the user **visits** the PT tab, regardless of minting.

Add `@AppStorage("PTReminder.unseenCapacity") private var unseenCapacity: Bool` in `MainTabView`.

- Set to `true` by `PositivityTokenReminder` when capacity rises above 0.
- Set to `false` in `ListPositivityTokenView.onAppear`.

Badge logic becomes:

```swift
.badge(mintCapacity > 0 && unseenCapacity ? 1 : 0)
```

#### Encouragement copy in PT list (PRD item 2)

In `ListPositivityTokenView`, when `capacity > 0`, show a section below the summary:

> *"You have [N] check-in[s] worth of positivity to capture. What's been going well?"*

Pure UI change in `ListView.swift` — no new infrastructure needed.

#### Push notification deep-link

Notification `userInfo`: `{ "destination": "pt-list" }`. Handle in `WilgoApp` via a `UNUserNotificationCenterDelegate` (or `onOpenURL` if using a URL scheme). Set `selectedTab = 2` on the `MainTabView`.

### Testing additions

- Unit test: `PositivityTokenReminder` sets `capacityBecamePositiveAt` when capacity rises from 0.
- Unit test: clears the flag when capacity drops to 0.
- Unit test: notification not re-scheduled if already sent for the same capacity window.
- Manual test: tap notification → lands on PT list tab; badge clears on tab visit.

---

## Commit Plan

Dependency order is explicit below. A commit marked **"blocks X"** must merge before X begins.  
Tests ship in the **same commit** as the source change they cover.

```
1 (Model + model tests)
├── 1.5 (Migration hardening — conditional, only if 1 breaks existing store)
└── blocks 2, 3
2 (Minting logic + minting tests)
│   └── blocks 4, 5, 6
3 (Undo cleanup + undo tests)
4 (AddView)
5 (ListView)
6 (MainTabView badge v1)
│   └── blocks 7
7 (FinishedCycleReport reasons + reasons tests)
8 (PositivityTokenReminder + seen flag + encouragement copy + reminder tests)
```

---

### Commit 1 — Model: remove PT↔CheckIn relationship + model tests

**Blocks:** 1.5 (if needed), 2, 3  
**Files:** `PositivityToken.swift`, `CheckIn.swift`; update existing model tests

- Remove `@Relationship var checkIn: CheckIn?` from `PositivityToken`.
- Remove `var positivityToken: PositivityToken?` from `CheckIn`.
- Update `PositivityToken.init` to drop the `checkIn` parameter.
- Fix all compile errors (tests/previews that pass a check-in to the init or read `.positivityToken`).
- **Tests:** update any existing test that constructs a PT with a check-in link; add a test confirming a `PositivityToken` can be inserted without a linked check-in.

---

### Commit 1.5 — Migration hardening *(conditional — only if Commit 1 breaks an existing store)*

**Requires:** 1 | **Blocks:** 2, 3  
**Files:** new `WilgoSchemaV1.swift`, `WilgoSchemaV2.swift`, `WilgoMigrationPlan.swift`; update `WilgoApp.swift`

- Introduce `VersionedSchema` + `SchemaMigrationPlan` (v1 = with relationship, v2 = without).
- Document the exact store error message in a PR comment.

---

### Commit 2 — Logic: replace window-based minting with capacity math + minting tests

**Requires:** 1 | **Blocks:** 4, 5, 6  
**Files:** `PositivityTokenMinting.swift`; new `PositivityTokenMintingTests.swift`

- Delete all window-based functions (`windowAfterCheckIn`, `isCheckInSponsorable`, `eligibleCheckIn`, `secondsRemainingInMintWindow`, `recentCheckInsLowerBound`, `fetchRecentCheckInsForMint`).
- Add `mintCapacity(tokenCount:checkInCount:) -> Int` and `canMint(tokenCount:checkInCount:) -> Bool`.
- Add `fetchTotalTokenCount(context:)` and `fetchTotalCheckInCount(context:)` helpers.
- **Tests:** `mintCapacity` / `canMint` edge cases (0 check-ins, equal counts, capacity > 0); `monthlyBudgetRemaining` helper logic; smoke test that `FinishedCycleReport` compensation still applies active PTs.

---

### Commit 3 — Remove PT deletion from undo closures + undo tests

**Requires:** 1  
**Files:** `WilgoApp.swift`, `BackfillSheet.swift`, `CommitmentStatsCard.swift`; update or add undo tests

- Remove `if let token = checkIn.positivityToken { context.delete(token) }` from all three undo closures.
- **Tests:** undo check-in → check-in deleted, PT count unchanged; backfill delete path same.

---

### Commit 4 — AddView: remove sponsoring check-in

**Requires:** 2  
**Files:** `AddView.swift`

- Remove `sponsoringCheckIn: CheckIn` parameter and all code referencing it.
- Remove `onReceive(.CheckInRevoked)` handler and `checkInUndoManager.dismissAll()` call.
- `saveToken()` → `PositivityToken(reason: trimmedReason)` (no check-in arg).
- *(No new unit tests — view behavior is covered by the minting tests in Commit 2 and manual checklist.)*

---

### Commit 5 — ListView: summary + capacity-aware UI

**Requires:** 2  
**Files:** `ListView.swift`

- Remove `MintWindowBanner`, `TimelineView` wrapper, polling tasks, `sponsoringCheckIn` state, `CheckInRevoked` handler.
- Add summary section (Created / Used / Active / Monthly budget remaining).
- Add capacity row: "N mints available" or *"Create more check-ins to mint more PTs."*
- Gate `+` toolbar button and sheet on capacity.
- *(Seen-flag `.onAppear` wired in Commit 8 — leave a `TODO` comment here.)*

---

### Commit 6 — MainTabView: red dot badge (v1, capacity-only)

**Requires:** 2 | **Blocks:** 8  
**Files:** `MainTabView.swift`

- Replace `sponsorableCheckIns` query + `mintBadgeClock` + `onChange` with `@Query var allTokens` + `@Query var allCheckIns`.
- Badge: `.badge(mintCapacity > 0 ? 1 : 0)`.
- *(Seen-flag refinement comes in Commit 8.)*

---

### Commit 7 — FinishedCycleReport: exact reasons copy + reasons tests

**Requires:** 1  
**Files:** `PositivityTokenCompensator.swift`, `Models.swift`, `PositivityTokenPage.swift`; update `PositivityTokenCompensatorTests.swift`

- Change `PositivityTokenCompensator.apply` return type to `[String: [String]]` (cycleID → ordered reason strings).
- Add `consumedPTReasons: [String]` to `CycleReport`; derive `aidedByPositivityTokenCount` from `.count`.
- Update `AfterPositivityTokenReportBuilder` to pass reasons through.
- Update `CycleResultRow` in `PositivityTokenPage` to render the PRD waiver copy.
- **Tests:** compensator returns reasons in FIFO order; `consumedPTReasons` is empty for unaided and grace cycles.

---

### Commit 8 — PositivityTokenReminder + seen flag + encouragement copy + reminder tests

**Requires:** 2, 6  
**Files:** new `PositivityTokenReminder.swift`; update `WilgoApp.swift`, `MainTabView.swift`, `ListView.swift`; new `PositivityTokenReminderTests.swift`

- Add `PositivityTokenReminder` enum: BGTask registration, hourly in-app scheduler, capacity-change detection (UserDefaults watermark), push notification scheduling, `unseenCapacity` flag management.
- Wire into `WilgoApp` `scenePhase` handler and `init`.
- Update `MainTabView` badge: `.badge(mintCapacity > 0 && unseenCapacity ? 1 : 0)`.
- Update `ListPositivityTokenView.onAppear` to clear `unseenCapacity`.
- Add encouragement copy section in `ListView` when capacity > 0.
- Add notification deep-link handling (`destination: pt-list` → select PT tab).
- **Tests:** `PositivityTokenReminder` sets `capacityBecamePositiveAt` when capacity rises from 0; flag cleared when capacity drops to 0; notification not re-scheduled if already sent for same capacity window.
- Manual test note (in PR): tap notification → PT list tab; badge clears on visit.

---

## Testing Checklist

**Core (Commits 1–6):**

[x] Mint when `capacity > 0`; cannot mint when `capacity == 0`;  
[x] Undo check-in: check-in removed; PT rows and count unchanged.  
[x] Backfill undo path: same as above.  
[x] `FinishedCycleReport`: active PTs still compensate misses; monthly cap still respected.  
[x] Summary header shows correct Created / Used / Active / Monthly remaining counts.  
[x] Tab badge shows red dot when capacity > 0 and capacity just increased and before user clicks the PT tab.  
[x] `AddPositivityTokenView` no longer references any check-in.
[x] **Upgrade path:** install old build → create check-ins + PTs → install new build → store opens, data intact.
[x] Widget launches against shared store after upgrade (smoke).

**Reasons copy (Commit 7):**

[x] Aided cycle in `PositivityTokenPage` shows reason strings, not just count.  
[ ] Unaided and grace cycles show no reasons copy. --- need future verification with newly created 

**Notifications (Commit 8): ------- POSTPONED, AI did not accomplish this part correctly, so mark it for future. **  
[ ] Push notification fires when new capacity is created.  
Not working reliablly, when the app just launch there is a push notification, but not when i check-in using Widget's AppIntent.  
[ ] Tapping notification navigates to PT list tab.  
[ ] Notification not re-sent for the same capacity window.

---

## Open Items (deferred per PRD)

- In-app banner when check-in is done while app is open (PRD item 4, "later").
- Weekly reminder if capacity > 0 and no mint for 7 days (PRD item 5, "maybe").
- Wordcloud / danmu background in PT list.
- Notifications for checking-in made not directly on App. 

