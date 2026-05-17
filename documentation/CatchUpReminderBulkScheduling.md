# CatchUp Reminder — Bulk Pre-Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** N/A (engineering improvement)  
**Tracking:** [catch-up reminder rework](https://www.notion.so/catch-up-reminder-rework-3624b58e32c3809b8d93e619e0e977bb?source=copy_link)  
**Tag:** `#CatchUpBulkScheduling`

---

**Goal:** Replace the single "schedule one → fire → schedule next" catch-up notification with bulk pre-scheduling of up to 10 exponential-backoff notifications so the chain survives even if iOS never fires the BGAppRefreshTask.

**Architecture:** On every rebuild trigger, `CatchUpReminder` computes all fire dates in the chain at once, cancels the 10 fixed notification IDs, and re-submits all of them in one pass. The BGAppRefreshTask and hourly in-app tick remain as content-freshness mechanisms, not chain-continuity mechanisms.

**Tech Stack:** Swift, UserNotifications, BackgroundTasks, SwiftData, Swift Testing

---

## Context

The old flow: schedule one notification → it fires → BGAppRefreshTask wakes the app → schedule the next one. iOS throttles BGAppRefreshTask heavily; if it doesn't fire, the chain dies silently and the user gets no more catch-up reminders.

The fix: pre-schedule all 10 fire dates up-front every time we rebuild. Even if the app is never woken again, all 10 notifications are already queued in iOS. On each rebuild (hourly tick, app→background, BGAppRefreshTask, app→active) we cancel-and-resubmit to keep content fresh.

---

## Backoff Sequence

From `lastNewCatchUpCommitmentDate` (the moment a new catch-up was first detected):

| Index | Offset | Rationale |
|-------|--------|-----------|
| 0 | 0 h | Immediate |
| 1 | 1 h | |
| 2 | 3 h | |
| 3 | 7 h | |
| 4 | 15 h | |
| 5 | 24 h (1 day) | Rounded from 31 h |
| 6 | 48 h (2 days) | Rounded from 63 h |
| 7 | 96 h (4 days) | Rounded from 127 h |
| 8 | 168 h (1 week) | Rounded from 255 h |
| 9 | 336 h (2 weeks) | Rounded from 511 h |
| 10 | 672 h (4 weeks) | Rounded from 1023 h |

Cap: schedule only dates **strictly in the future** (>= now), up to a max of 10 pending notifications (IDs `wilgo.catchup.0` … `wilgo.catchup.9`).

---

## Design Decisions

### Single-ID → Indexed IDs

**Decision:** Replace `"wilgo.catchup"` with `"wilgo.catchup.0"` … `"wilgo.catchup.9"`.

**Why:** iOS holds up to 64 pending notifications per app. We need stable IDs to cancel and resubmit the whole chain atomically. Fixed indices let us remove all 10 IDs without fetching pending requests first.

**Risk:** Old single ID `"wilgo.catchup"` may still be pending from a previous install. Mitigation: also remove `"wilgo.catchup"` during the migration rebuild (include it in the cancel list).

### Keep All Existing Rebuild Triggers + Add `.active`

**Decision:** Keep hourly tick, app→background, BGAppRefreshTask. Add app→active as a new trigger.

**Why:** The hourly tick keeps content fresh while the app is open (catch-up set changes every hour). BGAppRefreshTask is now truly just a backstop. App→active catches widget/Live Activity check-ins that happened while app was backgrounded.

### No BGAppRefreshTask removal

**Decision:** Keep the BGAppRefreshTask even though it's no longer chain-critical.

**Why:** It's a cheap, free freshness update if iOS grants it. Removing it has no benefit.

---

## File Changes

| File | Change |
|------|--------|
| `Wilgo/Features/Notifications/CatchUpReminder.swift` | Replace `scheduleNotificationPost` with bulk-scheduling; expose `catchUpOffsetHours` as `internal` for tests; remove `nextNotificationDate`; update `notificationIDs` |
| `Wilgo/WilgoApp.swift` | Add `CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()` to the `.active` branch of the scene phase handler |
| `WilgoTests/Notifications/CatchUpReminderTests.swift` | New test file |

---

## Commit Plan

### Phase 1 — Core logic change

#### Commit 1 — Refactor CatchUpReminder to bulk-schedule up to 10 notifications `#CatchUpBulkScheduling`

**Modify:** `Wilgo/Features/Notifications/CatchUpReminder.swift`

Replace the entire file with the following. Key changes:
- `notificationIDs`: array of 10 indexed IDs + legacy ID for migration cleanup
- `catchUpOffsetHours`: `internal static let` array of 11 offsets (marked `internal` so tests can read it)
- `fireDates(from:now:)`: pure function — returns future dates only, capped at 10
- `scheduleNotificationPost`: cancel all IDs, then submit one request per future fire date
- Remove `nextNotificationDate` (replaced by `fireDates`)

```swift
import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

enum CatchUpReminder {
    // MARK: - Notification IDs

    // Legacy single-ID kept here so we cancel it during migration.
    private static let legacyNotificationID = "wilgo.catchup"
    private static let notificationIDPrefix = "wilgo.catchup."
    static let maxPendingCount = 10

    // All IDs we own — used for bulk cancel.
    private static var allNotificationIDs: [String] {
        (0..<maxPendingCount).map { "\(notificationIDPrefix)\($0)" } + [legacyNotificationID]
    }

    // MARK: - Backoff offsets

    // Offsets in hours from lastNewCatchUpCommitmentDate.
    // internal so tests can verify the sequence without duplicating it.
    static let catchUpOffsetHours: [Double] = [
        0, 1, 3, 7, 15,
        24,   // 1 day
        48,   // 2 days
        96,   // 4 days
        168,  // 1 week
        336,  // 2 weeks
        672,  // 4 weeks
    ]

    // MARK: - In-app scheduler

    private static var scheduler: InAppScheduler?
    static func startHourlyRunWhileActive() {
        guard scheduler == nil else { return }
        scheduler = InAppScheduler(interval: 60 * 60) {
            Task { @MainActor in
                CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
        scheduler?.start()
    }

    // MARK: - Background task

    private static let backgroundTaskIdentifier = "wilgo.catchup-reminder-scheduler"
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                updateAndScheduleNotificationAndBackgroundTask()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - Main entry point

    @MainActor
    static func updateAndScheduleNotificationAndBackgroundTask(
        now: Date? = nil
    ) {
        let now = now ?? Time.now()
        let context = ModelContext(WilgoApp.sharedModelContainer)
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let remindersOn = commitments.filter(\.isRemindersEnabled)
        let catchUp = CommitmentAndSlot.catchUpWithBehind(commitments: remindersOn)

        updateCatchUpCommitmentsStorage(catchUp: catchUp, now: now)
        scheduleNotificationPost(for: catchUp, now: now)
        scheduleBackgroundTask(now: now)
    }

    // MARK: - Background task scheduling

    static func scheduleBackgroundTask(now _: Date) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(1 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - UserDefaults storage

    private static let lastNewCatchUpCommitmentDateKey =
        "CatchUpReminderService.lastNewCatchUpCommitmentDate"
    private static let lastCatchUpCommitmentsKey: String =
        "CatchUpReminderService.lastCatchUpCommitments"

    private static func updateCatchUpCommitmentsStorage(
        catchUp: [CommitmentAndSlot.WithBehind],
        now: Date = Time.now()
    ) {
        let defaults = UserDefaults.standard
        let currentIDs = Set(catchUp.map(\.0.id))

        let prevRawIDs = defaults.stringArray(forKey: lastCatchUpCommitmentsKey) ?? []
        let prevIDs = Set(prevRawIDs.compactMap { UUID(uuidString: $0) })

        let newIDs = currentIDs.subtracting(prevIDs)
        if !newIDs.isEmpty {
            defaults.set(now, forKey: lastNewCatchUpCommitmentDateKey)
        }

        defaults.set(currentIDs.map(\.uuidString), forKey: lastCatchUpCommitmentsKey)
    }

    // MARK: - Fire date computation

    /// Returns up to `maxPendingCount` future fire dates anchored at `anchorDate`.
    /// Dates in the past (< now) are skipped; the chain starts from the first future offset.
    static func fireDates(from anchorDate: Date, now: Date) -> [Date] {
        catchUpOffsetHours
            .map { anchorDate.addingTimeInterval($0 * 3600) }
            .filter { $0 > now }
            .prefix(maxPendingCount)
            .map { $0 }
    }

    // MARK: - Notification content

    private static func makeNotificationContent(
        for catchUp: [CommitmentAndSlot.WithBehind]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default

        guard !catchUp.isEmpty else {
            content.title = "Catch up on your commitments"
            content.body = "Open Wilgo to review your commitments."
            return content
        }

        let commitments = catchUp.map(\.0)
        let count = commitments.count

        if count == 1, let commitment = commitments.first {
            content.title = "Catch up: \(commitment.title)"
            content.body = "You have 1 commitment to catch up on. Open Wilgo to do it now."
            return content
        }

        content.title = "Catch up on \(count) commitments"
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        if titles.count > 3 {
            content.body = "\(primary) · +\(titles.count - 3) more"
        } else {
            content.body = primary
        }
        return content
    }

    // MARK: - Notification scheduling

    private static func scheduleNotificationPost(
        for catchUp: [CommitmentAndSlot.WithBehind], now: Date
    ) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            // Cancel the entire chain (including legacy single-ID).
            center.removePendingNotificationRequests(withIdentifiers: allNotificationIDs)

            guard !catchUp.isEmpty else { return }

            guard
                let anchorDate = UserDefaults.standard.object(
                    forKey: lastNewCatchUpCommitmentDateKey) as? Date
            else { return }

            let dates = fireDates(from: anchorDate, now: now)
            let content = makeNotificationContent(for: catchUp)

            for (index, fireDate) in dates.enumerated() {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(notificationIDPrefix)\(index)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
}
```

**tracking:** https://www.notion.so/catch-up-reminder-rework-3624b58e32c3809b8d93e619e0e977bb?source=copy_link

---

#### Commit 2 — Add `.active` scene phase rebuild trigger `#CatchUpBulkScheduling`

**Modify:** `Wilgo/WilgoApp.swift`

In the `onChange(of: scenePhase)` handler, add `CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()` to the `.active` branch:

```swift
.onChange(of: scenePhase) { _, newPhase in
    SlotStartNotificationScheduler.refresh()

    if newPhase == .active {
        NowLiveActivityManager.workAndScheduleNextBGTask()
        CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()  // ADD THIS LINE
    } else {
        CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
        NowLiveActivityManager.workAndScheduleNextBGTask()
        SlotStartNotificationScheduler.scheduleBackgroundTask()
    }
}
```

**tracking:** https://www.notion.so/catch-up-reminder-rework-3624b58e32c3809b8d93e619e0e977bb?source=copy_link

---

### Phase 2 — Tests

#### Commit 3 — Add CatchUpReminderTests `#CatchUpBulkScheduling`

**Create:** `WilgoTests/Notifications/CatchUpReminderTests.swift`

```swift
import Foundation
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CatchUpReminderTests {

    // MARK: - Helpers

    private func date(
        year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    // MARK: - catchUpOffsetHours shape

    @Test("offset sequence has exactly 11 entries")
    func offsetSequence_hasElevenEntries() {
        #expect(CatchUpReminder.catchUpOffsetHours.count == 11)
    }

    @Test("offset sequence is strictly increasing")
    func offsetSequence_isStrictlyIncreasing() {
        let offsets = CatchUpReminder.catchUpOffsetHours
        for i in 1..<offsets.count {
            #expect(offsets[i] > offsets[i - 1])
        }
    }

    @Test("first offset is 0 (immediate)")
    func offsetSequence_firstIsZero() {
        #expect(CatchUpReminder.catchUpOffsetHours.first == 0)
    }

    @Test("last offset is 672 hours (4 weeks)")
    func offsetSequence_lastIsFourWeeks() {
        #expect(CatchUpReminder.catchUpOffsetHours.last == 672)
    }

    // MARK: - fireDates(from:now:)

    @Test("all offsets in the future are returned when anchor == now")
    func fireDates_allFuture_whenAnchorEqualsNow() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        let now = anchor  // anchor == now: offset 0 is NOT > now, so it's skipped

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        // offset 0 produces a date == now, which is not > now, so excluded
        #expect(result.count == CatchUpReminder.catchUpOffsetHours.count - 1)
    }

    @Test("dates strictly in the past are excluded")
    func fireDates_pastDatesExcluded() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        // now is 3 hours after anchor — offsets 0 h and 1 h are in the past
        let now = date(year: 2026, month: 1, day: 1, hour: 3)

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        // offsets 0h, 1h, 3h all produce dates <= now → excluded
        // first included: 7h offset
        #expect(result.first == anchor.addingTimeInterval(7 * 3600))
    }

    @Test("result is capped at maxPendingCount")
    func fireDates_cappedAtMaxPendingCount() {
        // anchor far in the past so all 11 offsets produce future dates... except
        // we cap at maxPendingCount (10)
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        let now = date(year: 2025, month: 12, day: 31)  // now before anchor

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        #expect(result.count == CatchUpReminder.maxPendingCount)
    }

    @Test("returns empty when all offsets are in the past")
    func fireDates_allPast_returnsEmpty() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        // now is far beyond the last offset (672 h = 28 days)
        let now = date(year: 2026, month: 3, day: 1)

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        #expect(result.isEmpty)
    }

    @Test("each date corresponds to correct offset from anchor")
    func fireDates_datesMatchOffsets() {
        let anchor = date(year: 2026, month: 1, day: 1, hour: 0)
        let now = date(year: 2025, month: 12, day: 31)  // all in future

        let result = CatchUpReminder.fireDates(from: anchor, now: now)

        // First 10 offsets (maxPendingCount) should match exactly
        let expectedOffsets = CatchUpReminder.catchUpOffsetHours.prefix(CatchUpReminder.maxPendingCount)
        for (resultDate, offset) in zip(result, expectedOffsets) {
            let expected = anchor.addingTimeInterval(offset * 3600)
            #expect(resultDate == expected)
        }
    }
}
```

Run tests:
```bash
./test-with-cleanup.sh 2>&1 | grep -E "(CatchUpReminderTests|PASS|FAIL|error:)"
```

Expected: all 8 new tests pass. Pre-existing failing test `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence` is unrelated — ignore it.

**tracking:** https://www.notion.so/catch-up-reminder-rework-3624b58e32c3809b8d93e619e0e977bb?source=copy_link

---

## Critical Files

| File | Role |
|------|------|
| `Wilgo/Features/Notifications/CatchUpReminder.swift` | Core change — bulk scheduling logic |
| `Wilgo/WilgoApp.swift` | Add `.active` trigger |
| `WilgoTests/Notifications/CatchUpReminderTests.swift` | New test file |

## Dependency Graph

```
Commit 1: Refactor CatchUpReminder to bulk-schedule
    |
    +-- Commit 2: Add .active scene phase trigger  [parallel after 1]
    +-- Commit 3: Add CatchUpReminderTests          [parallel after 1]
```

Commits 2 and 3 are independent of each other and can be parallelized after Commit 1.

---

## Verification

1. Run `./test-with-cleanup.sh` — all 8 new `CatchUpReminderTests` should pass.
2. Build and launch on iPhone 17 simulator (`4492FF84-2E83-4350-8008-B87DE7AE2588`). App must not crash.
3. Manually verify: in Simulator, open Settings → Notifications → Wilgo. After launching the app, use `lldb` or add a temporary `print` to confirm `center.pendingNotificationRequests` contains up to 10 `wilgo.catchup.*` IDs.
4. Confirm legacy `"wilgo.catchup"` ID is absent from pending list after first rebuild.
