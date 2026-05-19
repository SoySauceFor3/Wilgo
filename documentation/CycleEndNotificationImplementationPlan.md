# Cycle-End Notification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** N/A (discussed in conversation — no formal PRD)
**Tracking:** [add a notification at the end of cycle to tell user a report is generated](https://www.notion.so/add-a-notification-at-the-end-of-cycle-to-tell-user-a-report-is-generated-3394b58e32c3806d8dd5dc5c589375f5?source=copy_link)
**Tag:** `#CycleEndNotification`

---

## Context

Users sometimes don't open the app and miss the cycle-end report. The goal is a **re-engagement local notification** delivered at the moment a cycle ends, nudging the user to open the app and view their report. No backend — fully on-device.

**Design decisions made during brainstorming:**

- **Generic copy only** ("Your cycle just ended. Tap to see how it went.") — dynamic completion stats (e.g. "8/10 check-ins") would be ideal but require knowing the stat at schedule time, which is impossible on-device. Reschedule-on-every-check-in was considered and rejected as fragile.
- **Re-engagement framing** — retention nudge, not an informational "report exists" alert.
- **Considered but rejected:** Achievement hook ("You completed X/Y check-ins") and Reflection hook ("How'd this cycle go?") — both appealing but require dynamic data unavailable at schedule time.
- **Midnight (00:00) delivery** — fire at the exact cycle-end boundary. The user needs time to see and tap the notification, so by the time they open the app the psych-day has flipped and the report is ready.
- **Repeating triggers considered and rejected** — would only work if all commitments of the same type share the same anchor. `referencePsychDay` allows arbitrary anchors (retained for future custom N-day cycles), so repeating triggers are not safe. Scan-and-schedule is used instead.

---

## Architecture Summary

When `FinishedCycleReportModifier` detects a finished cycle (on scene activation), it already shows the in-app report. We add a new `CycleEndNotificationScheduler` that runs **alongside** this existing check — not inside it — to schedule repeating notifications for each cycle type present among the user's commitments.

The scheduler:

1. Runs on scene activation (same trigger as the report modifier).
2. Fetches all commitments and determines which `CycleKind`s are in use (daily, weekly, monthly).
3. Schedules one repeating `UNNotificationRequest` per active cycle type, replacing any previously scheduled ones.
4. Uses one fixed notification ID per type (`"wilgo.cycle-end.daily"`, `"wilgo.cycle-end.weekly"`, `"wilgo.cycle-end.monthly"`) for clean cancellation.

**Why repeating triggers are safe here:** All weekly commitments share the same Monday anchor; all monthly share the 1st. So a single repeating trigger fires at the correct time for every commitment of that type. When custom N-day cycles are added in future, this approach will be revisited for that type only.

---

## Design Decisions

### One repeating notification per active cycle type

**Decision:** Schedule one repeating `UNCalendarNotificationTrigger` per `CycleKind` that exists among the user's commitments. Max 3 notifications total.

**Why not scan-and-schedule per commitment?** All commitments of the same type share the same fixed anchor (weekly → Monday, monthly → 1st), so one repeating trigger covers all of them. Scanning forward and deduplicating is unnecessary complexity until custom cycles exist.

**Why only schedule types in use?** No point firing a weekly notification if the user has no weekly commitments.

**Risk:** If the user removes all commitments of a given type, the notification for that type would still fire. **Mitigation:** Cancel-and-reschedule on every scene activation — inactive types get their notifications removed.

### No new background task

**Decision:** Do not register a `BGAppRefreshTask` for this scheduler.

**Why:** Cycle-end dates are stable (change only when the user edits a commitment). Refreshing on scene activation is sufficient. The slot-start background task already keeps the app warm, so cycle-end notifications will be rescheduled forward whenever the user does open the app.

### Notification delivery at midnight (00:00)

**Decision:** Fire at `endDayOfCycle` exactly — which is midnight, the start of the next cycle day.

**Why:** `endDayOfCycle` returns the exclusive end (first day of next cycle) at midnight. Firing at midnight is clean and correct. By the time the user sees the notification and taps it (~seconds to hours later), the psych-day has already flipped and `FinishedCycleReportModifier` will show the report correctly. A later time (e.g. 9 AM) was considered but rejected — no strong UX reason to delay, and midnight is simpler (fire date = cycle end date directly, no offset math).

---

## Major Model Changes


| Entity                                                                      | Change                                                             |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| **New:** `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` | Schedules local notifications for upcoming cycle ends              |
| `Wilgo/WilgoApp.swift`                                                      | Call `CycleEndNotificationScheduler.refresh()` on scene activation |


---

## Commit Plan

### Commit 1 — feat: add CycleEndNotificationScheduler #CycleEndNotification

**Create:** `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift`

```swift
import Foundation
import SwiftData
import UserNotifications

enum CycleEndNotificationScheduler {
    private static let notificationIDPrefix = "wilgo.cycle-end."

    private static var allNotificationIDs: [String] {
        CycleKind.allCases.map { "\(notificationIDPrefix)\($0.rawValue.lowercased())" }
    }

    // MARK: - Main entry point

    @MainActor
    static func refresh() {
        let context = ModelContext(WilgoApp.sharedModelContainer)
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let activeKinds = Set(commitments.map(\.cycle.kind))
        scheduleNotifications(for: activeKinds)
    }

    // MARK: - Trigger computation

    /// Returns a repeating UNCalendarNotificationTrigger that fires at midnight
    /// at the end of each period for the given cycle kind.
    ///
    /// - Daily:   fires every day at 00:00 (weekday/day unset → repeats daily)
    /// - Weekly:  fires every Monday at 00:00
    /// - Monthly: fires on the 1st of every month at 00:00 (= end of previous month's cycle)
    static func trigger(for kind: CycleKind) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = 0
        components.minute = 0
        components.second = 0
        switch kind {
        case .daily:
            break // no day component → repeats every day
        case .weekly:
            components.weekday = 2 // Monday
        case .monthly:
            components.day = 1 // 1st of month = exclusive end of previous month's cycle
        }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    // MARK: - Notification content

    private static func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Your cycle just ended"
        content.body = "Tap to see how it went."
        content.sound = .default
        return content
    }

    // MARK: - Scheduling

    private static func scheduleNotifications(for activeKinds: Set<CycleKind>) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            // Cancel all owned notifications, then re-schedule only active kinds.
            center.removePendingNotificationRequests(withIdentifiers: allNotificationIDs)

            let content = makeContent()
            for kind in activeKinds {
                let request = UNNotificationRequest(
                    identifier: "\(notificationIDPrefix)\(kind.rawValue.lowercased())",
                    content: content,
                    trigger: trigger(for: kind)
                )
                center.add(request)
            }
        }
    }
}
```

**Modify:** `Wilgo/WilgoApp.swift` — in `onChange(of: scenePhase)`, add `CycleEndNotificationScheduler.refresh()` in the `.active` branch alongside `SlotStartNotificationScheduler.refresh()`.

**Create:** `WilgoTests/Notifications/CycleEndNotificationSchedulerTests.swift`

```swift
import Testing
import Foundation
@testable import Wilgo

@Suite("CycleEndNotificationScheduler")
struct CycleEndNotificationSchedulerTests {

    // MARK: - trigger(for:)

    @Test func trigger_daily_repeatsEveryDay() {
        let trigger = CycleEndNotificationScheduler.trigger(for: .daily)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.minute == 0)
        #expect(trigger.dateComponents.weekday == nil)
        #expect(trigger.dateComponents.day == nil)
    }

    @Test func trigger_weekly_firesSundayMidnight() {
        let trigger = CycleEndNotificationScheduler.trigger(for: .weekly)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.weekday == 2) // 2 = Sunday
        #expect(trigger.dateComponents.day == nil)
    }

    @Test func trigger_monthly_firesFirstOfMonth() {
        let trigger = CycleEndNotificationScheduler.trigger(for: .monthly)
        #expect(trigger.repeats == true)
        #expect(trigger.dateComponents.hour == 0)
        #expect(trigger.dateComponents.day == 1)
        #expect(trigger.dateComponents.weekday == nil)
    }
}
```

> **Note:** Use `makeContainer()` from any existing test file (e.g. `WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift`) if you add model-based tests. Verify `Commitment` init signatures against `Shared/Models/Commitment.swift` before running.

- Create `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` with the code above.
- In `Wilgo/WilgoApp.swift`, add `CycleEndNotificationScheduler.refresh()` in the `.active` branch of `onChange(of: scenePhase)`.
- Create `WilgoTests/Notifications/CycleEndNotificationSchedulerTests.swift` with the tests above.
- Run only the new tests:
  ```bash
  xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
    -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
    -only-testing WilgoTests/CycleEndNotificationSchedulerTests \
    2>&1 | tail -40
  ```
  Expected: all PASS.
- Run full test suite:
  ```bash
  ./test-with-cleanup.sh 2>&1 | tail -40
  ```
  Expected: no new failures beyond pre-existing `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence`.
- Commit:
  ```bash
  git add Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift \
    Wilgo/WilgoApp.swift \
    WilgoTests/Notifications/CycleEndNotificationSchedulerTests.swift
  git commit -m "$(cat <<'EOF'
  feat: add CycleEndNotificationScheduler #CycleEndNotification

  Schedules one repeating local notification per active cycle type (daily/
  weekly/monthly) at midnight when the cycle ends, to re-engage users who
  haven't opened the app. Only schedules kinds present among the user's
  commitments; cancels stale notifications on each scene activation.

  tracking: https://www.notion.so/add-a-notification-at-the-end-of-cycle-to-tell-user-a-report-is-generated-3394b58e32c3806d8dd5dc5c589375f5
  EOF
  )"
  ```

---

## Critical Files


| File                                                                      | Role                                    |
| ------------------------------------------------------------------------- | --------------------------------------- |
| `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift` (new)  | Core scheduler                          |
| `Wilgo/WilgoApp.swift`                                                    | Wire up `refresh()` on scene activation |
| `WilgoTests/Notifications/CycleEndNotificationSchedulerTests.swift` (new) | Unit tests                              |


---

## Dependency Graph

```
Commit 1: scheduler + wire-up + tests (single commit)
```

---

## Manual Verification

After the commit, on iPhone 17 Simulator (UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`):

1. Launch the app. Grant notification permission if prompted.
2. Open Settings → Notifications → Wilgo — confirm notifications are enabled.
3. Verify via Xcode console that `CycleEndNotificationScheduler.refresh()` runs on scene activation (add a temporary `print` if needed) and that `UNNotificationRequest` objects are added without error.

