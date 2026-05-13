# Phase 1b — Per-Slot-Start Notifications Implementation Plan

**PRD:** [Notification 05/09/26](https://www.notion.so/Notification-05-09-26-35b4b58e32c38008be3eed5a40e67a6e) (Phase 1b section)  
**Tracking:** [per slot start notification](https://www.notion.so/per-slot-start-notification-35b4b58e32c3801ea0e3ff3d53676b92)  
**Tag:** `#perSlotNotification`

---

## Context

Phase 1a (already complete) extracted `slotStatus(now:)` and `goalProgress(now:)` from `stageStatus`. Phase 1b uses these APIs to schedule one local notification per slot-start time across all reminders-enabled commitments. Notifications are pre-scheduled in bulk (up to 48) so iOS — not our app — fires them, making them resilient to background-task throttling.

---

## Architecture Summary

A new `SlotStartNotificationScheduler` enum (matching `CatchUpReminder`'s stateless pattern) owns all scheduling logic. Its single public entry point is `refresh(now:)`, which:

1. Fetches all `isRemindersEnabled` commitments from `WilgoApp.sharedModelContainer.mainContext`.
2. Forward-projects each commitment's slot starts using `slotStatus(now: candidateSlotStart)` + `goalProgress(now: candidateSlotStart)`. Skips fire dates where the slot would be saturated or goal already met by check-ins-known-now.
3. Groups candidate fire dates by exact timestamp (aggregation). Builds one `UNNotificationRequest` per unique fire time, with title/body/actions as specified in the PRD.
4. Removes all existing pending requests whose identifiers carry the slot-start prefix, then submits the new set (capped at 48).

`refresh(now:)` is called from:

- `WilgoApp` on scene becoming `.active`
- `WilgoApp.onChange(scenePhase != .active)` — the existing "last chance" path (alongside `CatchUpReminder`)
- The Darwin notification observer (after widget CheckIn/Snooze intents fire)
- The new `BGAppRefreshTask` handler
- After any commitment create / edit / delete (via save path in `AddCommitmentView`, `EditCommitmentView`, `ListCommitmentView`)

`WilgoApp` sets a `UNUserNotificationCenterDelegate` (during `init`) to handle:

- `didReceive`: route single-commitment tap to `wilgo://commitment?id=<UUID>`; multi-commitment tap falls through to default (opens app, Stage view)

---

## Design Decisions

### Notification identifier scheme

**Decision:** Identifiers use the prefix `wilgo.slot-start.` followed by the ISO8601 representation of the fire date (e.g., `wilgo.slot-start.2026-05-12T08:00:00Z`). One identifier per unique slot-start timestamp.

**Why not per-commitment identifiers?** The PRD requires aggregation: multiple commitments starting at the same moment produce one notification. A timestamp-keyed identifier naturally implements this — building the aggregated request for that time either creates or replaces the single entry. Per-commitment identifiers would require additional deduplication logic.

**Risk:** Two slot starts within the same second (very unlikely given minute-granularity slots) would collide. Acceptable: slots are always user-defined on minute boundaries.

### Notification categories for action buttons

**Decision:** Register two `UNNotificationCategory` values:

- `wilgo.slot-start.single` — actions: **Check In** (`CheckInIntent`), **Snooze** (`SnoozeIntent`)
- `wilgo.slot-start.multi` — no actions

Single-commitment notifications get `categoryIdentifier = "wilgo.slot-start.single"` with `userInfo` carrying `commitmentId` and `slotId`. Multi-commitment notifications get `categoryIdentifier = "wilgo.slot-start.multi"` with `userInfo` carrying a `commitmentIds` array (for possible future use).

**Why two categories instead of one conditional?** `UNNotificationCategory` action sets are static (registered at launch). The distinction between single/multi determines the action set, so two categories is the clean model. One category with runtime action suppression is not how the API works.

**Note on `CheckInIntent` / `SnoozeIntent` from notifications:** These are `AppIntent`s currently used by the Live Activity widget extension. Notification action buttons backed by `AppIntent` require the intent to be declared in the main app target too (or a shared framework). Both intents currently live only in `WidgetExtension`. They need to be moved to the `Shared` target (or duplicated with `openAppWhenRun: false`) so the notification action can invoke them. See Commit 1.

### `UNUserNotificationCenterDelegate` placement

**Decision:** Implement the delegate on a new `NotificationDelegate` class instantiated and held as a `private let` on `WilgoApp`, set as `UNUserNotificationCenter.current().delegate` during `WilgoApp.init()`. Only `didReceive` is implemented — no `willPresent` (foreground suppression is not needed).

**Why not directly on `WilgoApp`?** `WilgoApp` is a `struct` (SwiftUI `App` protocol). Delegates must be reference types (`NSObject` subclasses for `UNUserNotificationCenterDelegate`). A dedicated class keeps the delegate lifetime tied to the app's lifetime without hacks.

### Darwin notification path for widget intents

**Decision:** Extend the existing `NowLiveActivityManager.startObservingIntentNotifications()` observer (which already fires on `WilgoConstants.liveActivitySyncNotification`) to also call `SlotStartNotificationScheduler.refresh()`. No new Darwin notification name needed.

**Why not a separate observer?** The Darwin notification already fires on exactly the events we need (check-in or snooze from widget). Sharing the observer avoids registering duplicate CFNotificationCenter observers.

---

## Major Model Changes


| Entity                                                                       | Change                                                                                                                                                                                              |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **New:** `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` | Core scheduler: `refresh()`, scheduling logic, `BGAppRefreshTask` handler                                                                                                                           |
| **New:** `Wilgo/Features/Notifications/NotificationDelegate.swift`           | `UNUserNotificationCenterDelegate`: `didReceive` only                                                                                                                                               |
| `Wilgo/WilgoApp.swift`                                                       | Hold `NotificationDelegate`; register it; call `SlotStartNotificationScheduler.registerBackgroundTask()` and `refresh()` on scene-phase changes; add `wilgo.slot-start-scheduler` BGTask identifier |
| `Wilgo/Info.plist`                                                           | Add `wilgo.slot-start-scheduler` to `BGTaskSchedulerPermittedIdentifiers`                                                                                                                           |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift`                  | Extend Darwin observer to also call `SlotStartNotificationScheduler.refresh()`                                                                                                                      |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`                    | Call `SlotStartNotificationScheduler.refresh()` after save                                                                                                                                          |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`                   | Call `SlotStartNotificationScheduler.refresh()` after save                                                                                                                                          |
| `Wilgo/Features/Commitments/ListCommitmentView.swift`                        | Call `SlotStartNotificationScheduler.refresh()` after delete                                                                                                                                        |
| **Move/share:** `CheckInIntent.swift`, `SnoozeIntent.swift`                  | Add to `Shared` target so notification action buttons can invoke them from the main app                                                                                                             |


No SwiftData model changes. No new persisted schema.

---

## Proposed Key Signatures

```swift
// SlotStartNotificationScheduler.swift
enum SlotStartNotificationScheduler {
    static let backgroundTaskIdentifier = "wilgo.slot-start-scheduler"
    static let notificationIdentifierPrefix = "wilgo.slot-start."
    static let maxPendingCount = 48
    // Upper bound on how far ahead to enumerate slot starts. Without this, a user
    // with 1 slot/day would enumerate years of future dates before hitting the 48-cap.
    // 14 days is wide enough for the near future and cheap to compute.
    static let horizonDays = 14

    static func registerBackgroundTask()
    @MainActor static func refresh(now: Date = Time.now())
    static func scheduleBackgroundTask()

    // Internal helpers (fileprivate)
    // - candidateFireDates(for commitments: [Commitment], from now: Date) -> [Date: [Commitment]]
    // - makeRequest(for commitments: [Commitment], at fireDate: Date) -> UNNotificationRequest
    // - makeSingleContent(commitment: Commitment, slot: Slot?) -> UNMutableNotificationContent
    // - makeMultiContent(commitments: [Commitment]) -> UNMutableNotificationContent
}

// NotificationDelegate.swift
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_:didReceive:withCompletionHandler:)
}
```

---

## Commit Plan

### Phase 1 — Core scheduler (notifications fire end-to-end)

Goal: get notifications firing at slot starts as fast as possible. No action buttons or tap routing yet.

#### Commit 1 — `SlotStartNotificationScheduler` core: scheduling logic + unit tests

**Modify:** `Wilgo/Info.plist`
- Add `wilgo.slot-start-scheduler` to `BGTaskSchedulerPermittedIdentifiers`.

**Create:** `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift`

```swift
enum SlotStartNotificationScheduler {
    static let backgroundTaskIdentifier = "wilgo.slot-start-scheduler"
    static let notificationIdentifierPrefix = "wilgo.slot-start."
    static let maxPendingCount = 48
    // Upper bound on how far ahead to enumerate slot starts. Without this, a user
    // with 1 slot/day would enumerate years of future dates before hitting the 48-cap.
    // 14 days is wide enough for the near future and cheap to compute.
    static let horizonDays = 14

    @MainActor
    static func refresh(now: Date = Time.now()) {
        let context = WilgoApp.sharedModelContainer.mainContext
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let remindersOn = commitments.filter { $0.isRemindersEnabled }

        let grouped = candidateFireDates(for: remindersOn, from: now)
        let sorted = grouped.keys.sorted().prefix(maxPendingCount)
        let requests = sorted.compactMap { date -> UNNotificationRequest? in
            guard let cs = grouped[date] else { return nil }
            return makeRequest(for: cs, at: date)
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.getPendingNotificationRequests { pending in
                let oldIDs = pending.map(\.identifier)
                    .filter { $0.hasPrefix(notificationIdentifierPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)
                for request in requests { center.add(request) }
            }
        }
    }

    // Returns [slotStartDate: [Commitment]] for all upcoming eligible slot starts
    // within horizonDays from now, capped implicitly by maxPendingCount in refresh().
    private static func candidateFireDates(
        for commitments: [Commitment],
        from now: Date
    ) -> [Date: [Commitment]] {
        var result: [Date: [Commitment]] = [:]
        let horizon = Time.calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        for commitment in commitments {
            var dayCursor = Time.startOfDay(for: now)
            while dayCursor < horizon {
                for slot in commitment.slots {
                    guard let occurrence = slot.resolveOccurrence(on: dayCursor) else { continue }
                    let fireDate = occurrence.start
                    guard fireDate > now else { continue }

                    // Forward-project eligibility using check-ins known now (best-effort).
                    let projectedSlot = commitment.slotStatus(now: fireDate)
                    let projectedGoal = commitment.goalProgress(now: fireDate)
                    guard !projectedGoal.isMet else { continue }
                    guard projectedSlot.kind == .insideSlot ||
                          projectedSlot.remainingSlots.contains(where: { $0.start == occurrence.start })
                    else { continue }

                    result[fireDate, default: []].append(commitment)
                }
                dayCursor = Time.calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? horizon
            }
        }
        return result
    }

    private static func makeRequest(
        for commitments: [Commitment],
        at fireDate: Date
    ) -> UNNotificationRequest {
        let content: UNMutableNotificationContent
        if commitments.count == 1, let c = commitments.first {
            let slot = c.slots.first(where: {
                $0.resolveOccurrence(on: Time.startOfDay(for: fireDate))?.start == fireDate
            })
            content = makeSingleContent(commitment: c, slot: slot)
        } else {
            content = makeMultiContent(commitments: commitments)
        }
        content.sound = .default

        let identifier = notificationIdentifierPrefix + ISO8601DateFormatter().string(from: fireDate)
        let components = Time.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func makeSingleContent(
        commitment: Commitment, slot: Slot?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for: \(commitment.title)"
        content.body = commitment.encouragements.randomElement() ?? slot?.timeOfDayText ?? ""
        content.userInfo = ["commitmentId": commitment.id.uuidString,
                            "slotId": slot?.id.uuidString ?? ""]
        return content
    }

    private static func makeMultiContent(commitments: [Commitment]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(commitments.count) commitments starting now"
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        content.body = titles.count > 3 ? "\(primary) · +\(titles.count - 3) more" : primary
        content.userInfo = ["commitmentIds": commitments.map { $0.id.uuidString }]
        return content
    }
}
```

**Create:** `WilgoTests/Notifications/SlotStartNotificationSchedulerTests.swift`

Tests (in-memory `ModelContainer`; test scheduling logic only — no real `UNUserNotificationCenter` calls):

- `candidateFireDates_singleCommitment_oneSlot_returnsSlotStart`
- `candidateFireDates_pastSlotStart_excluded`
- `candidateFireDates_goalAlreadyMet_excluded`
- `candidateFireDates_slotSaturated_excluded`
- `candidateFireDates_twoCommitmentsAtSameTime_groupedTogether`
- `candidateFireDates_remindersDisabled_excluded`
- `candidateFireDates_beyondHorizon_excluded`
- `makeRequest_singleCommitment_titleContainsCommitmentTitle`
- `makeRequest_multiCommitment_titleContainsCount`
- `makeRequest_singleWithEncouragement_bodyIsEncouragement`
- `makeRequest_singleNoEncouragement_bodyIsSlotTimeText`

**Verification:** `xcodebuild test -only-testing:WilgoTests/SlotStartNotificationSchedulerTests` passes.

---

#### Commit 2 — BGAppRefreshTask + wire into `WilgoApp` scene phase

**Add to `SlotStartNotificationScheduler`:**

```swift
static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: backgroundTaskIdentifier,
        using: nil
    ) { task in
        guard let refreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false); return
        }
        Task { @MainActor in
            refresh()
            scheduleBackgroundTask()
            refreshTask.setTaskCompleted(success: true)
        }
    }
}

static func scheduleBackgroundTask() {
    let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(24 * 60 * 60)  // daily-ish
    try? BGTaskScheduler.shared.submit(request)
}
```

**Modify:** `Wilgo/WilgoApp.swift`

In `init()`:
```swift
SlotStartNotificationScheduler.registerBackgroundTask()
```

In `.onChange(of: scenePhase)`:
```swift
if newPhase == .active {
    NowLiveActivityManager.workAndScheduleNextBGTask()
    SlotStartNotificationScheduler.refresh()  // ADD
} else {
    CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
    SlotStartNotificationScheduler.refresh()  // ADD
    NowLiveActivityManager.workAndScheduleNextBGTask()
}
```

**Verification:** Build passes. Full test suite green.

**Manual verification:** Add a commitment with a slot starting ~2 minutes from now. Force-quit the app. Wait for slot start. Confirm notification fires on simulator lock screen.

---

#### Commit 3 — Wire into Darwin observer + save/delete paths

**Modify:** `Wilgo/Features/Notifications/NowLiveActivityManager.swift`

Extend the Darwin observer callback in `startObservingIntentNotifications()`:
```swift
Task { @MainActor in
    NowLiveActivityManager.workAndScheduleNextBGTask()
    SlotStartNotificationScheduler.refresh()  // ADD
}
```

**Modify:** `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`  
After `try? modelContext.save()`: add `SlotStartNotificationScheduler.refresh()`

**Modify:** `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`  
After `try? modelContext.save()`: add `SlotStartNotificationScheduler.refresh()`

**Modify:** `Wilgo/Features/Commitments/ListCommitmentView.swift`  
After `modelContext.delete(...)`: add `SlotStartNotificationScheduler.refresh()`

**Verification:** Build passes. Full test suite green.

**Manual verification:**
- Toggle `isRemindersEnabled` off → pending slot-start notifications removed on next refresh.
- Delete a commitment → its notifications removed.
- Check in via widget → refresh fires (Darwin path).

---

### Phase 2 — Action buttons + tap routing

Goal: add Check In / Snooze action buttons and deep-link tap routing.

#### Commit 4 — Move intents to Shared target + register notification categories

**Modify target membership:** `WidgetExtension/CheckInIntent.swift`, `WidgetExtension/SnoozeIntent.swift`
- Add both to the `Wilgo` (main app) target so they compile into both targets.

**Modify:** `Wilgo/WilgoApp.swift` `init()` — register two notification categories:

```swift
let singleCategory = UNNotificationCategory(
    identifier: "wilgo.slot-start.single",
    actions: [
        UNNotificationAction(identifier: "CHECK_IN", title: "Check In", options: []),
        UNNotificationAction(identifier: "SNOOZE",   title: "Snooze",   options: [])
    ],
    intentIdentifiers: [], options: []
)
let multiCategory = UNNotificationCategory(
    identifier: "wilgo.slot-start.multi",
    actions: [], intentIdentifiers: [], options: []
)
UNUserNotificationCenter.current().setNotificationCategories([singleCategory, multiCategory])
```

**Modify:** `SlotStartNotificationScheduler.makeRequest` — set `categoryIdentifier` on the content:
- Single-commitment: `content.categoryIdentifier = "wilgo.slot-start.single"`
- Multi-commitment: `content.categoryIdentifier = "wilgo.slot-start.multi"`

**Note:** Action button invocation wiring (mapping `CHECK_IN` / `SNOOZE` action identifiers to `CheckInIntent` / `SnoozeIntent`) is handled in Commit 5 via `didReceive`.

**Verification:** Build passes (both targets). Full test suite green.

**Manual verification:** Trigger a slot-start notification. Long-press it — confirm Check In and Snooze buttons appear on single-commitment notification; none on multi.

---

#### Commit 5 — `NotificationDelegate`: tap routing + action button handling

**Create:** `Wilgo/Features/Notifications/NotificationDelegate.swift`

```swift
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "CHECK_IN":
            if let idStr = userInfo["commitmentId"] as? String,
               let uuid = UUID(uuidString: idStr) {
                Task { try? await CheckInIntent(commitmentId: uuid, source: .notification).perform() }
            }
        case "SNOOZE":
            if let idStr = userInfo["slotId"] as? String,
               let uuid = UUID(uuidString: idStr) {
                Task { try? await SnoozeIntent(slotId: uuid).perform() }
            }
        default:
            // Tap (no action): route single-commitment to CommitmentDetailView
            if let idStr = userInfo["commitmentId"] as? String {
                let url = URL(string: "wilgo://commitment?id=\(idStr)")!
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }
            // Multi-commitment tap: no-op — app opens to Stage view by default
        }
        completionHandler()
    }
}
```

**Modify:** `Wilgo/WilgoApp.swift`
- Add `private let notificationDelegate = NotificationDelegate()` stored property.
- In `init()`: `UNUserNotificationCenter.current().delegate = notificationDelegate`

**Verification:** Build passes. Full test suite green.

**Manual verification:**
- Tap single-commitment notification → `CommitmentDetailView` opens.
- Tap multi-commitment notification → Stage view opens.
- Press Check In action → commitment checked in.
- Press Snooze action → slot snoozed.

---

### Phase 3 — Final validation

#### Commit 6 — End-to-end success criteria check

Checkpoint against all PRD success criteria. No code changes expected; if bugs are found, each is a separate commit.

1. Force-quit app → slot-start notification fires at correct time.
2. Multiple commitments at same start → one notification, not N.
3. Toggle reminders off → future notifications removed.
4. Delete commitment → notifications removed.
5. Snooze → refresh removes pending notification.
6. Check in meeting goal → notifications removed.
7. Single-commitment tap → `CommitmentDetailView` opens.
8. Multi-commitment tap → Stage view opens.
9. Total pending notifications never exceeds 50.

---

## Critical Files

| File                                                                          | Role                                       |
| ----------------------------------------------------------------------------- | ------------------------------------------ |
| **New:** `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift`  | Core scheduler                             |
| **New:** `Wilgo/Features/Notifications/NotificationDelegate.swift`            | `didReceive`: tap routing + action buttons |
| **New:** `WilgoTests/Notifications/SlotStartNotificationSchedulerTests.swift` | Unit tests for scheduling logic            |
| `Wilgo/WilgoApp.swift`                                                        | Wiring: BGTask, scene phase, delegate      |
| `Wilgo/Info.plist`                                                            | BGTask identifier registration             |
| `Wilgo/Features/Notifications/NowLiveActivityManager.swift`                   | Extend Darwin observer                     |
| `Wilgo/Features/Commitments/Form/AddCommitmentView.swift`                     | Refresh on create                          |
| `Wilgo/Features/Commitments/Form/EditCommitmentView.swift`                    | Refresh on edit                            |
| `Wilgo/Features/Commitments/ListCommitmentView.swift`                         | Refresh on delete                          |
| `WidgetExtension/CheckInIntent.swift`                                         | Add to main app target (Commit 4)          |
| `WidgetExtension/SnoozeIntent.swift`                                          | Add to main app target (Commit 4)          |

### Dependency Graph

```
Commit 1 (Scheduler core + tests + Info.plist)
    |
    +-- Commit 2 (BGTask + WilgoApp scene phase wiring)
            |
            +-- Commit 3 (Darwin observer + save/delete wiring)   ← notifications fully fire
                    |
                    +-- Commit 4 (Intents to Shared + categories)
                            |
                            +-- Commit 5 (NotificationDelegate: tap + actions)
                                    |
                                    +-- Commit 6 (End-to-end validation)
```

---

## Manual Verification

Required at Commits 2, 3, 4, 5, and 6. Real notifications cannot be unit-tested end-to-end.

Key simulator steps (Commits 2 / 6):
1. Add a commitment with `isRemindersEnabled = true` and a slot starting ~2 minutes from now.
2. Force-quit the app.
3. Wait for the slot start time.
4. Confirm the notification appears on the simulator lock screen.

