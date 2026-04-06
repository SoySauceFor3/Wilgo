# Widgets Implementation

PRD: [https://www.notion.so/Type-1-PRD-3394b58e32c380a78848edaf8276ee6f?source=copy_link](https://www.notion.so/Type-1-PRD-3394b58e32c380a78848edaf8276ee6f?source=copy_link)

We deisgn the implementation of "current commitment here". But a lot of the design is generic to all the widgets which will be created in the future. A lot of domain knowledge and rules are relevant, so documenting the decisions here.

# 1.Reuse the existing `WidgetExtension` Target

Apple requires all widgets and Live Activities from the same app to live in one widget extension bundle. If you created a second widget extension target, the App Store would reject it — apps are only allowed one widget extension. The WidgetBundle is exactly the mechanism for hosting multiple widgets/Live Activities in that single target:

```swift
@main
struct WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        NowLiveActivity()  // existing
        Widget()              // new widget goes here
    }
}
```

NowLiveActivity and the new Now widget coexist in the same target, compiled together, sharing the same sandbox. That's the intended design.

Overall framework to use: ios's WidgetKit and AppIntent --- common pattern to implement Widget in ios.

# 2. Use `AppIntent`

`AppIntent` is chosen to implement the button to file a `CheckIn` in the widget. `AppIntent` (iOS 17+) runs **in the widget extension process itself** — the app never opens. The check-in is recorded silently and the widget updates in place.

Alternative: a `Link(destination:)` which opens the app and delivers a URL. But that means:

- The app must come to the foreground just to record a check-in
- There's a visible app-launch transition — bad UX for a one-tap action

Using `AppIntent` means that we have to put target `Wilgo` and target `WidgetExtension` under the same `App Group`. Here is how you do that

## Manual Set Up To Configure App Group

1. **[x] Apple Developer Portal** ([developer.apple.com](http://developer.apple.com) → Certificates, Identifiers & Profiles → Identifiers → App Groups → "+"): Create App Group `group.xyz.soysaucefor3.wilgo`. Enable it on both App IDs: `xyz.soysaucefor3.Wilgo` (main app) and `xyz.soysaucefor3.Wilgo.WidgetExtension` (widget).
  **NOTE**: not creating the group beforehand on web is fine. The step below allows group creation directly from XCode.
2. **[x] Xcode — main app target**: Signing & Capabilities → "+" → App Groups → add `group.xyz.soysaucefor3.wilgo`
3. **[x] Xcode — WidgetExtension target**: same as above
4. **[ ] Xcode — target membership**: After creating the two new `Shared/` files, set Target Membership to both `Wilgo` and `WidgetExtension` in the File Inspector (same pattern as `Shared/NowAttributes.swift`)

## Move SwiftData Store to the App Group

`AppIntent` requires moving the SwiftData store to the App Group.

The `AppIntent` runs inside the **widget extension process** (not the main app). It needs to write a `CheckIn` to SwiftData. But by default, the SwiftData store lives at:

```
/private/var/mobile/Containers/Data/Application/<app-UUID>/Library/Application Support/default.store

```

That path is inside the **main app's sandbox** — the widget extension cannot access it.

To fix this, you move the store to the App Group container:

```
/private/var/mobile/Containers/Shared/AppGroup/<group-UUID>/Library/Application Support/default.store
```

Both processes can read/write there. In code, this means changing `ModelConfiguration` in `WilgoApp.swift` to use an explicit URL:

```swift
let groupURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.xyz.soysaucefor3.wilgo")!
    .appendingPathComponent("Library/Application Support/default.store")
let config = ModelConfiguration(schema: schema, url: groupURL)

```

The widget extension creates its own `ModelContainer` pointing to the same URL.

## 3. WidgetKit API - How widget works

### Key Functions

Wilgo App side:

- `reloadTimelines()` **doesn't "broadcast" data** — it just tells WidgetKit "hey, my data has changed, please ask me for a new timeline."

Widget side:

`getTimeline` and `getSnapshot` are two callbacks WidgetKit calls on the widget's `TimelineProvider`:

- `getSnapshot` — called when the widget gallery preview is shown. Must return quickly (no async work).
- `getTimeline` — called when WidgetKit needs to know what to display. Can do work, but ideally fast.

The full sequence:

```
1. Something changes (check-in created, app backgrounded, etc.)
   ↓
2. App calls WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")
   ↓
3. WidgetKit calls getTimeline() on your TimelineProvider
   ↓
4. getTimeline() queries the shared SwiftData store
   ↓
5. Returns a Timeline with one or more entries
   ↓
6. WidgetKit renders the widget with those entries
```

One extra thing: `reloadTimelines()` is not the only trigger for `getTimeline()`. WidgetKit also calls it automatically:
At the `nextRefreshDate` you specify in the `Timeline`'s policy (`.after(date)`)
When the system decides it's a good time (background refresh budget)
So even without `reloadTimelines()`, the widget will eventually self-refresh. But `reloadTimelines()` makes it **immediate** — that's why you call it after a check-in so the count updates right away instead of waiting for the next scheduled refresh.

### Where should WIdgetKit API get data

Let's compare all options:


| Approach                                                       | `getSnapshot`        | `getTimeline` | `CheckInIntent` write                   | Complexity                                    |
| -------------------------------------------------------------- | -------------------- | ------------- | --------------------------------------- | --------------------------------------------- |
| **A: Shared SwiftData (direct query)**                         | Query store          | Query store   | Write to store                          | Medium — one shared store, no cache layer     |
| **B: Shared UserDefaults cache + shared SwiftData for writes** | Read cache (instant) | Read cache    | Write to store + invalidate cache       | Higher — two sources of truth to keep in sync |
| **C: UserDefaults cache only, no SwiftData in widget**         | Read cache           | Read cache    | AppIntent can't write (no store access) | ❌ Incompatible with AppIntent                 |


**Option A is better.** Here's why Option B's cache is not worth it:

- `getSnapshot` is called for the widget gallery preview. SwiftData queries on a local file are fast enough — no noticeable lag.
- `getTimeline` is not on the critical path for UI responsiveness.
- A cache introduces a second source of truth. If the cache goes stale (app crashes before writing, etc.), the widget shows wrong data.
- With a shared store you get **one source of truth**: the widget always shows exactly what's in the database.

### Data Flow

```
App process                          Widget process
─────────────────────────────        ─────────────────────────────
Check-in created (any source)
  ↓
Save to shared SwiftData store  ←──→  Same store file
  ↓
WidgetCenter.reloadTimelines()  ──→   getTimeline() called
                                        ↓
                                      Query shared SwiftData store
                                        ↓
                                      Return entry with fresh data

User taps "+" on widget:
                                      CheckInIntent runs in widget process
                                        ↓
                                      Write CheckIn to shared store
                                        ↓
                                      WidgetCenter.reloadTimelines()
                                        ↓
                                      getTimeline() called → fresh data
```

# 4. Major Interaction Implementation

## Check-in via AppIntents

- `CheckInIntent: AppIntent` is defined in the WidgetExtension target
- It receives the commitment id (maybe as encoded `PersistentIdentifier)`, opens the shared SwiftData store, creates a `CheckIn`, saves, then reloads the widget timeline
- The "+" button in the widget view is wrapped in `Button(intent: CheckInIntent(commitmentId: ...))`
- Requires iOS 17+. No paid Apple Developer account needed for development and testing.

## Navigation from widget card (WidgetKit `Link` API)

No AppIntent is needed for navigation. WidgetKit has a built-in mechanism:

- The commitment card (excluding the "+" button) is wrapped in `Link(destination: URL(string: "wilgo://commitment?id=\\(encodedId)")!)`. Tapping it launches the app and delivers the URL via `onOpenURL`.
- A new `case "commitment":` is added to the existing `handleDeepLink(_:)` in `WilgoApp.swift`. It decodes the commitment ID, looks up the `Commitment`, and presents `CommitmentDetailView` as a sheet.
- `CommitmentDetailView` already exists at `Wilgo/Features/Commitments/SingleCommitment/CommitmentDetailView.swift` — no new screen needs to be built.
- The "+" button uses `Button(intent: CheckInIntent(...))` as a separate tappable region inside the card.

## When to call `reloadTimelines()` — keeping the widget up to date

### Two complementary mechanisms

**Timeline policy** (works even when app is killed):

`getTimeline` returns `Timeline(entries: [...], policy: .after(nextTransitionDate))` where `nextTransitionDate` comes from `CommitmentAndSlot.nextTransitionDate()`. WidgetKit automatically calls `getTimeline` again at that date — no app involvement needed. This covers:

- Slot window opening or closing
- Psychological day boundary (cycle reset)

`**reloadTimelines()` called explicitly** (app must be alive, but user-driven events require the app anyway):

- Check-in created or undone
- Commitment added, edited, or deleted

### Where to add `reloadTimelines()` in the app

From a code search, check-ins are created in 4 places and deleted in 3. However, all of them already call through `CheckInUndoManager.enqueue(...)`. So rather than touching every call site, add `reloadTimelines()` in **two places in `CheckInUndoManager`**:

1. Inside `enqueue(...)` — fires after every check-in creation
2. Inside the undo closure — fires after every undo/delete

This is the single-responsibility approach: the undo manager already owns check-in lifecycle, so widget refresh belongs there too.

```
Event                          → Trigger
──────────────────────────────   ──────────────────────────────────────────────
Slot opens / closes            → Timeline policy .after(nextTransitionDate)  ✅ works when killed
Psychological day boundary     → Timeline policy .after(nextTransitionDate)  ✅ works when killed
Check-in created (any source)  → CheckInUndoManager.enqueue()
Check-in undone                → CheckInUndoManager undo closure
Commitment added/deleted       → reloadTimelines() at EditCommitmentView / ListCommitmentView call sites
Widget "+" tapped              → CheckInIntent.perform() calls reloadTimelines() directly
```

> **Note on background/killed state**: When the app is killed, `reloadTimelines()` cannot run — there is no process. The Timeline policy covers all time-based changes. Check-in and commitment mutations require user interaction, which means the app is open, so `reloadTimelines()` will always be reachable for those events.

# 5. Files to Create / Modify


| **Action** | **Path**                                                                                                     | **Notes**                                                                                                                                                                                |
| ---------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modify     | `Wilgo/WilgoApp.swift`                                                                                       | Move SwiftData store URL to App Group container; add `wilgo://commitment` deep-link case presenting `CommitmentDetailView`                                                               |
| Create     | `WidgetExtension/CurrentCommitmentWidget.swift`                                                              | `TimelineEntry`, `TimelineProvider`, all widget views (small/medium/large/empty), `Widget` struct, previews                                                                              |
| Create     | `WidgetExtension/CheckInIntent.swift`                                                                        | `AppIntent` for the "+" button: opens shared store, inserts `CheckIn`, calls `WidgetCenter.reloadTimelines()`                                                                            |
| Modify     | `WidgetExtension/WidgetBundle.swift`                                                                         | Add `CurrentCommitmentWidget()` alongside `NowLiveActivity()`                                                                                                                            |
| Modify     | `Wilgo/Features/Commitments/CheckInUndo/CheckInUndoManager.swift`                                            | Call `WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")` in `enqueue()` (creation) and the undo closure (deletion) — single hook covering all app-side check-in mutations |
| Modify     | `Wilgo/Features/Commitments/EditCommitmentView.swift`, `Wilgo/Features/Commitments/ListCommitmentView.swift` | Call `reloadTimelines()` after commitment add/delete so the widget reflects structural changes                                                                                           |


**No new Shared/ files needed** — the widget queries SwiftData directly from the shared store. No snapshot struct, no UserDefaults cache.

**Already done (manual Xcode setup):**

- `Wilgo/WilgoDebug.entitlements` — App Group `group.xyz.soysaucefor3.wilgo` ✅
- `Wilgo/WilgoRelease.entitlements` — App Group `group.xyz.soysaucefor3.wilgo` ✅
- `WidgetExtension/WidgetExtensionDebug.entitlements` — App Group `group.xyz.soysaucefor3.wilgo` ✅
- `WidgetExtension/WidgetExtensionRelease.entitlements` — App Group `group.xyz.soysaucefor3.wilgo` ✅

# 6. Key Existing Code to Reuse


| **Symbol**                                               | **File**                                          | **Purpose in widget**                                            |
| -------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------- |
| `CommitmentAndSlot.currentWithBehind(commitments:now:)`  | `Wilgo/Shared/Scheduling/CommitmentAndSlot.swift` | Get ordered list of currently active commitments                 |
| `commitment.checkInsInCycle(cycle:until:inclusive:)`     | `Wilgo/Shared/Models/Commitment.swift`            | Count check-ins in the current cycle                             |
| `CommitmentAndSlot.nextTransitionDate(commitments:now:)` | `Wilgo/Shared/Scheduling/CommitmentAndSlot.swift` | Compute `nextRefreshDate` for the Timeline policy                |
| `CycleKind.thisNoun`                                     | `Wilgo/Shared/Models/Cycle.swift`                 | Natural-language label: `"today"`, `"this week"`, `"this month"` |
| `slot.timeOfDayText`                                     | `Wilgo/Shared/Models/Slot.swift`                  | `"3:00 PM – 5:00 PM"` string for the card secondary line         |
| `PersistentIdentifier.encoded()` / `.decode(from:)`      | `Wilgo/WilgoApp.swift`                            | Encode commitment ID into `wilgo://commitment?id=` URL           |
| `Time.psychDay(for:)`                                    | `Wilgo/Shared/Scheduling/Time.swift`              | Current psychological day for cycle queries                      |


# 7. Major Type Definitions

Key types the widget implementation works with directly.

### `Commitment` (SwiftData model — existing)

```swift
// Wilgo/Shared/Models/Commitment.swift
@Model final class Commitment {
    var title: String
    var checkIns: [CheckIn]        // all historical check-ins
    var slots: [Slot]              // scheduled time windows
    var target: Target             // QuantifiedCycle: how many times per cycle
    var gracePeriods: [GracePeriod]
}
func checkInsInCycle(cycle: Cycle, until psychDay: Date, inclusive: Bool) -> [CheckIn]
func stageStatus(now: Date) -> StageStatus  // categorises as .current, .future, etc.
```

### `Target` / `QuantifiedCycle` (existing)

```swift
// Wilgo/Shared/Models/Commitment.swift
struct QuantifiedCycle: Codable {
    var cycle: Cycle  // the reset cycle (daily/weekly/monthly + anchor)
    var count: Int    // target check-in count per cycle
}
typealias Target = QuantifiedCycle
```

### `Cycle` + `CycleKind` (existing)

```swift
// Wilgo/Shared/Models/Cycle.swift
enum CycleKind: String, CaseIterable, Codable {
    case daily, weekly, monthly
    var thisNoun: String  // "today" / "this week" / "this month"
}
struct Cycle: Codable {
    var kind: CycleKind
    var multiplier: Int   // e.g. 2 = bi-weekly
}
func startDayOfCycle(including psychDay: Date) -> Date
func endDayOfCycle(including psychDay: Date) -> Date
func label(of date: Date) -> String  // "03/04" or "03/02 – 03/08"
```

### `CheckIn` (SwiftData model — existing)

```swift
// Wilgo/Shared/Models/CheckIn.swift
@Model final class CheckIn {
    var commitment: Commitment?
    var createdAt: Date
    var psychDay: Date              // logical calendar day (respects dayStartHourOffset)
    var timeZoneIdentifier: String
    // init auto-computes psychDay from createdAt + current timezone
}
```

### `Slot` (SwiftData model — existing)

```swift
// Wilgo/Shared/Models/Slot.swift
@Model final class Slot {
    var start: Date                 // time-of-day only (arbitrary reference day)
    var end: Date                   // time-of-day only
    var recurrence: SlotRecurrence  // everyDay / specificWeekdays / specificMonthDays
    var commitment: Commitment?
}
var timeOfDayText: String           // "3:00 PM – 5:00 PM"
```

### `CommitmentAndSlot.WithBehind` (existing)

```swift
// Wilgo/Shared/Scheduling/CommitmentAndSlot.swift
typealias WithBehind = (commitment: Commitment, slots: [Slot], behindCount: Int)

static func currentWithBehind(commitments: [Commitment], now: Date) -> [WithBehind]
// Returns commitments with stageStatus == .current, sorted by soonest-to-end slot.
// slots[0] is the active slot (used for timeOfDayText).
```

### `CurrentCommitmentEntry` + `CommitmentSnapshot` (new — to be created)

```swift
// WidgetExtension/CurrentCommitmentWidget.swift
struct CurrentCommitmentEntry: TimelineEntry {
    let date: Date
    let snapshot: CommitmentSnapshot?  // nil = empty state
}

struct CommitmentSnapshot {
    let title: String
    let checkedInCount: Int
    let targetCount: Int
    let cycleLabel: String     // from CycleKind.thisNoun (multiplier==1) or cycle.label(of:)
    let slotTimeText: String?  // nil if no active slot
    let encodedId: String      // for Link URL: wilgo://commitment?id=<encodedId>
}
// Plain struct extracted from SwiftData query result in getTimeline.
// No SwiftData objects cross the timeline boundary.
```

### `CheckInIntent` (new — to be created)

```swift
// WidgetExtension/CheckInIntent.swift
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    @Parameter var commitmentId: String  // encoded PersistentIdentifier

    func perform() async throws -> some IntentResult {
        // 1. Build ModelContainer at shared App Group store URL
        // 2. Fetch Commitment by decoded PersistentIdentifier
        // 3. Insert CheckIn, save context
        // 4. WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")
        return .result()
    }
}
```

# 8. Verification Checklist

- Add a commitment with a slot covering the current time → widget shows title, `0/1 · today · [slot time]`
- Tap "+" → widget updates to `1/1 · today` without opening the app
- Tap the commitment card → app opens to `CommitmentDetailView` for that commitment
- No current commitment → empty state with moon icon shown
- Weekly cycle → label shows `this week`
- Monthly cycle → label shows `this month`
- Existing data preserved after store moves to App Group URL (migration check)

# 9. Commits Plan

Each commit is self-contained and the app must build after each one.

---

**Commit 1 — Move SwiftData store to App Group container**

File: `Wilgo/WilgoApp.swift`

Change `ModelConfiguration` to use the App Group container URL. If the store exists at the old default path, migrate it by copying/moving the file before opening the container.

> This is the foundational commit — nothing else can work until the store is at the shared URL.

---

**Commit 2 — Add `wilgo://commitment` deep-link to open `CommitmentDetailView`**

File: `Wilgo/WilgoApp.swift`

Add `case "commitment":` to `handleDeepLink(_:)`. Decode the commitment ID, fetch the matching `Commitment`, present `CommitmentDetailView` as a sheet.

---

**Commit 3 — `CheckInIntent`: AppIntent for widget check-in**

File: `WidgetExtension/CheckInIntent.swift` (new)

Define `CheckInIntent: AppIntent`. Opens a `ModelContainer` at the shared App Group store URL, fetches the `Commitment` by `PersistentIdentifier`, inserts a `CheckIn`, saves, calls `WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")`.

> Depends on Commit 1 — the store must be at the shared URL.

---

**Commit 4 — `CurrentCommitmentWidget`: full widget implementation**

File: `WidgetExtension/CurrentCommitmentWidget.swift` (new)

Define `CommitmentSnapshot`, `CurrentCommitmentEntry`, `CurrentCommitmentProvider` (`getSnapshot` + `getTimeline` — both query shared SwiftData store), small/medium/large/empty views, `CurrentCommitmentWidget` struct with `kind = "CurrentCommitment"`, and `#Preview` macros for each size + empty state.

> Depends on Commits 1 and 3.

---

**Commit 5 — Register widget in `WidgetBundle`**

File: `WidgetExtension/WidgetBundle.swift`

Add `CurrentCommitmentWidget()` alongside `NowLiveActivity()`.

> Depends on Commit 4.

---

**Commit 6 — Reload widget timeline after app-side mutations**

Files: all app-side check-in creation call sites (at minimum `WilgoApp.handleDeepLink` `"done"` case; search for other `CheckIn(commitment:)` initialisations).

Add `WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")` after each check-in save so the widget updates immediately.

(Alternatively maybe Call `WidgetCenter.shared.reloadTimelines(ofKind: "CurrentCommitment")` in `enqueue()` (creation) and the undo closure (deletion) in `Wilgo/Features/Commitments/CheckInUndo/CheckInUndoManager.swift` — single hook covering all app-side check-in mutations. Will decide which way to go later.

> Depends on Commit 4 (the kind string must be defined). Can be done alongside Commit 5.

