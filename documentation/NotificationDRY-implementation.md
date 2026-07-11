# Notification Scheduler DRY — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**PRD:** N/A — pure refactor + two consistency fixes, no user-facing behavior change intended.
**Tracking:** [DRY the notification scheduling logic (esp. the background one)](https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link)
**Tag**: #notification #DRY

---

## Context

`Wilgo/Features/Notifications/` grew four schedulers (NowLiveActivityManager, SlotStartNotificationScheduler, CatchUpReminder, CycleEndNotificationScheduler) that each copy-pasted the same BGAppRefreshTask register/submit boilerplate and notification-copy patterns. The recent setTaskCompleted-race fix (`302d01f`) had to be applied three times — proof the duplication is costing us. Two inconsistencies are hiding in the copies:

1. **Stale-context hazard**: NowLiveActivityManager/SlotStart read `mainContext` (with a comment explaining why fresh contexts see stale state), but CatchUpReminder and CycleEnd create fresh `ModelContext(container)` — exactly the hazard the comment warns about.
2. **Calendar divergence**: SlotStart builds `UNCalendarNotificationTrigger`s with `Time.calendar`, CatchUpReminder with `Calendar.current`. If they ever differ (timezone/week rules), fire times silently diverge.

This refactor also unblocks the `WilgoApp.swift` scene-phase TODO (background-time assertion): after it, all scheduler entry points share one awaitable shape.

**Goal:** One home each for (a) BGTask register/submit, (b) the main-context accessor, (c) date-trigger construction, (d) the "A · B · C · +N more" body format — fixing the two inconsistencies in the process.

**Architecture:** Four small helpers in `Wilgo/Features/Notifications/`, adopted by the existing schedulers. No behavior change except the two deliberate consistency fixes. The completion-race logic gets a protocol seam (`BGWakeTask`) so it is finally unit-testable.

**Tech Stack:** Swift / BackgroundTasks / UserNotifications / swift-testing (`@Test` + `#expect`). Project uses filesystem-synchronized groups — new files need **no pbxproj edits**.

---

## Design Decisions

### BGWake as an enum helper, not a protocol

**Decision:** A namespace enum `BGWake` with `register(_:work:)`, `handle(_:work:)`, `submit(_:earliestBeginDate:)`.

**Why not a** `BackgroundRefreshable` **protocol with default implementations?** The three schedulers differ only in identifier + work closure; a protocol with static requirements would force conformances and buy nothing but indirection. The enum keeps each scheduler's `registerBackgroundTask()` a one-liner that reads top-to-bottom.

**Risk:** none meaningful — pure extraction; the handler logic is byte-for-byte the pattern already committed in `302d01f`.

### `BGWakeTask` protocol seam for testability

**Decision:** `handle(_:work:)` takes `some BGWakeTask` (a 2-member protocol `BGTask` already satisfies) and returns the work `Task` handle, so tests can drive completion/expiration with a fake and await the outcome deterministically.

**Why not test through** `BGTaskScheduler`**?** `BGTask` cannot be instantiated and `register` only works for Info.plist-declared identifiers, once per process. The seam is the only way to unit test the race logic — the most correctness-critical code in the folder.

### Logged (not thrown, not silent) submit failures

**Decision:** `BGWake.submit` catches and logs via `Logger(subsystem: "wilgo", category: "BGWake")` at `.notice`, same persisted-diagnostics rationale as `LiveActivityRefresher.logger`.

**Why not keep** `try?`**?** `tooManyPendingTaskRequests`/`notPermitted` are exactly the errors that explain "the BG task never fired" during dogfood, and today they vanish. Why not throw? A failed submit must never abort a scheduling pass — the app-alive paths still did their work.

### The two consistency fixes ride on the extraction commits

`ModelContext.wilgoMain` adoption (Commit 2) and `Time.calendar` unification (Commit 3) are deliberate behavior changes, each isolated in its own commit so they can be reverted/bisected independently of the pure extractions.

---

## Major Model Changes

No SwiftData model changes.

| Entity                                                                               | Change                                                                            |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| **New:** `Wilgo/Features/Notifications/BGWake.swift`                                 | BGTask register/handle/submit helper + `BGWakeTask` seam                          |
| **New:** `Wilgo/Features/Notifications/ModelContext+WilgoMain.swift`                 | `ModelContext.wilgoMain` moved out of NowLiveActivityManager, now internal        |
| ~~New: `UNCalendarNotificationTrigger+FireOnce.swift`~~                              | **Dropped during execution** (3Sauce: shallow wrapper / over-abstraction) — Commit 3 became the one-line `Calendar.current` → `Time.calendar` fix |
| **New:** `Wilgo/Features/Notifications/NotificationText.swift`                       | `joinedTitles(_:visibleCount:)` shared body format                                |
| `NowLiveActivityManager.swift`                                                       | Adopt BGWake; drop private `wilgoMain` extension; remove stray leftover comment   |
| `SlotStartNotificationScheduler.swift`                                               | Adopt BGWake, `wilgoMain`, `fireOnce`, `joinedTitles`                             |
| `CatchUpReminder.swift`                                                              | Adopt BGWake, `wilgoMain` (fix), `fireOnce` (`Time.calendar` fix), `joinedTitles` |
| `CycleEndNotificationScheduler.swift`                                                | Adopt `wilgoMain` (fix)                                                           |
| **New:** `WilgoTests/Notifications/BGWakeTests.swift`                                | Completion-race tests via `FakeBGTask`                                            |
| **New:** `WilgoTests/Notifications/NotificationTextTests.swift`                      | Body-format tests                                                                 |

---

## Commit Plan

Commits are **logically independent but touch the same files**, so execute **sequentially 1 → 2 → 3 → 4** (no parallel subagents on these).

Per-commit verification (per CLAUDE.md): build + run the Notifications test bundle first; run the full suite via `./test-with-cleanup.sh` after the final commit. Known pre-existing failure `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()` is NOT a regression. Simulator: iPhone 17, UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`.

Every commit message ends with:

```
#notification #DRY
tracking: https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

---

### Commit 1 — Extract BGWake: one home for the BGTask register/handle/submit boilerplate

**Files:**

- Create: `Wilgo/Features/Notifications/BGWake.swift`
- Create: `WilgoTests/Notifications/BGWakeTests.swift`
- Modify: `Wilgo/Features/Notifications/NowLiveActivityManager.swift` (registerBackgroundTask, scheduleBackgroundTask, stray comment at ~line 48)
- Modify: `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` (registerBackgroundTask, scheduleBackgroundTask)
- Modify: `Wilgo/Features/Notifications/CatchUpReminder.swift` (registerBackgroundTask, scheduleBackgroundTask)

- [ ] **Step 1: Write the failing tests**

Create `WilgoTests/Notifications/BGWakeTests.swift`:

```swift
import Foundation
import Testing
@testable import Wilgo

/// Drives `BGWake.handle` through the `BGWakeTask` seam — a real `BGTask` cannot be
/// instantiated in tests, and `BGTaskScheduler.register` only accepts Info.plist-declared
/// identifiers once per process.
private final class FakeBGTask: BGWakeTask {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []
    func setTaskCompleted(success: Bool) { completions.append(success) }
}

struct BGWakeTests {
    @Test("reports success exactly once, only after the work has completed")
    @MainActor
    func handle_reportsSuccessAfterWork() async {
        let task = FakeBGTask()
        var workDone = false
        let handle = BGWake.handle(task) {
            // Completion must not have been reported while the work is still running.
            #expect(task.completions.isEmpty)
            workDone = true
        }
        await handle.value
        #expect(workDone)
        #expect(task.completions == [true])
    }

    @Test("installs an expiration handler synchronously")
    @MainActor
    func handle_installsExpirationHandler() {
        let task = FakeBGTask()
        BGWake.handle(task) {}
        #expect(task.expirationHandler != nil)
    }

    @Test("expiration cancels the work and reports failure exactly once")
    @MainActor
    func handle_expirationReportsFailureOnce() async {
        let task = FakeBGTask()
        let handle = BGWake.handle(task) {
            // Long-running work; cancellation makes the sleep return immediately.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
        // iOS reclaims the wake before the work body has even started (the work Task is
        // only enqueued on the main actor, which this test occupies).
        task.expirationHandler?()
        await handle.value
        // Exactly one completion (the failure) — the cancelled work must not add a second.
        #expect(task.completions == [false])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile (BGWake does not exist)**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing:WilgoTests/BGWakeTests
```

Expected: build FAILS with "cannot find 'BGWake' in scope".

- [ ] **Step 3: Create** `Wilgo/Features/Notifications/BGWake.swift`

```swift
import BackgroundTasks
import Foundation
import OSLog

/// Seam so `BGWake.handle`'s completion-race logic is unit-testable: a real `BGTask`
/// cannot be instantiated, and `BGTaskScheduler.register` only accepts Info.plist-declared
/// identifiers once per process.
protocol BGWakeTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: BGWakeTask {}

/// One home for the BGAppRefreshTask boilerplate shared by the schedulers in
/// `Features/Notifications`: registration (a completion-race-safe launch handler with an
/// expiration handler) and submission (replace-in-place, failures logged instead of swallowed).
enum BGWake {
    /// Persisted diagnostics, same rationale as `LiveActivityRefresher.logger`: dogfood runs
    /// are unattached; `.notice` entries survive in the system log store (filter subsystem
    /// "wilgo" in Console.app / `log collect`).
    private static let logger = Logger(subsystem: "wilgo", category: "BGWake")

    /// Register `work` as the launch handler for `identifier`.
    /// Must be called before any `submit` for the same identifier — i.e., from `App.init`.
    static func register(_ identifier: String, work: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task, work: work)
        }
    }

    /// Runs `work`, and only then reports completion: `setTaskCompleted` lets iOS suspend the
    /// process, so reporting before the work finishes would let it be killed mid-flight.
    /// If iOS reclaims the wake first (`expirationHandler` — a background wake has a limited
    /// runtime budget, roughly up to 30s for an app-refresh task, sometimes less), the work is
    /// cancelled and the task reported failed so it is retried rather than silently marked done.
    ///
    /// Returns the work `Task` so tests can await the outcome; production callers ignore it.
    @discardableResult
    static func handle(
        _ task: some BGWakeTask, work: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let workTask = Task { @MainActor in
            await work()
            // Cancellation means expiration already completed the task; completing twice
            // violates the BGTask API contract.
            guard !Task.isCancelled else { return }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            workTask.cancel()
            task.setTaskCompleted(success: false)
        }
        return workTask
    }

    /// Submit (or replace — BGTaskScheduler keeps one pending request per identifier) an
    /// app-refresh wake no earlier than `earliestBeginDate`.
    static func submit(_ identifier: String, earliestBeginDate: Date?) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // `tooManyPendingTaskRequests` / `notPermitted` are exactly what explains a
            // "the BG task never fired" dogfood mystery — worth a persisted trace, never
            // worth aborting a scheduling pass (app-alive paths already did their work).
            logger.notice(
                "submit(\(identifier, privacy: .public)) failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
```

- [ ] **Step 4: Run the BGWake tests to verify they pass**

Same command as Step 2. Expected: 3 tests PASS.

- [ ] **Step 5: Adopt in NowLiveActivityManager**

In `Wilgo/Features/Notifications/NowLiveActivityManager.swift`, replace the whole `registerBackgroundTask()` (currently lines 53–78) with:

```swift
    /// Register the BGAppRefreshTask handler. Must be called before any `submit()` — i.e., before
    /// `scheduleBackgroundTask()`.
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) {
            await workAndScheduleNextBGTask()
        }
    }
```

In `scheduleBackgroundTask()`, replace the last three lines (request creation + `try? submit`) with:

```swift
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: nextDate)
```

Also delete the stray leftover comment at the end of `apply()`:

```swift
        // IF there is statement, it would run before the refreshTask boy executes.
```

- [ ] **Step 6: Adopt in SlotStartNotificationScheduler**

Replace `registerBackgroundTask()` and `scheduleBackgroundTask()` (currently lines 48–76) with:

```swift
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) {
            // Re-schedule before the work so a mid-flight kill still leaves a wake queued.
            scheduleBackgroundTask()
            await refresh()
        }
    }

    static func scheduleBackgroundTask() {
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: Date().addingTimeInterval(24 * 60 * 60))
    }
```

- [ ] **Step 7: Adopt in CatchUpReminder**

Replace `registerBackgroundTask()` (currently lines 50–70) with:

```swift
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) {
            await updateAndScheduleNotificationAndBackgroundTask()
        }
    }
```

Replace the body of `scheduleBackgroundTask(now:)` (currently lines 105–111) with:

```swift
    /// Queue the next catch-up reminder.
    static func scheduleBackgroundTask(
        now _: Date
    ) {
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: Date().addingTimeInterval(1 * 60 * 60))
    }
```

If `BackgroundTasks` is now unimported-but-unused in any of the three schedulers, remove the import.

- [ ] **Step 8: Build + run the Notifications test bundle**

```bash
xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo \
  -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588' \
  -only-testing:WilgoTests/BGWakeTests \
  -only-testing:WilgoTests/CatchUpReminderTests \
  -only-testing:WilgoTests/SlotStartNotificationSchedulerTests \
  -only-testing:WilgoTests/CycleEndNotificationSchedulerTests
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add Wilgo/Features/Notifications/ WilgoTests/Notifications/
git commit -m "Extract BGWake: one home for BGTask register/handle/submit

The setTaskCompleted-race handler pattern (await work -> complete; expiration
cancels + fails) was copy-pasted across three schedulers; 302d01f had to fix it
three times. BGWake owns it once, behind a BGWakeTask seam that finally makes
the race logic unit-testable. submit() failures are now logged (persisted
os.Logger, subsystem wilgo) instead of swallowed by try?.

#notification
tracking: https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Commit 2 — Share ModelContext.wilgoMain; fix stale-context reads in CatchUp/CycleEnd

**Files:**

- Create: `Wilgo/Features/Notifications/ModelContext+WilgoMain.swift`
- Modify: `Wilgo/Features/Notifications/NowLiveActivityManager.swift` (delete private extension, lines 6–15)
- Modify: `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift:23`
- Modify: `Wilgo/Features/Notifications/CatchUpReminder.swift` (`updateAndScheduleNotificationAndBackgroundTask`, fresh-context line)
- Modify: `Wilgo/Features/Notifications/CycleEndNotificationScheduler.swift:19`

No new unit tests: the accessor is a one-line forward; "sees fresh state" is inherently an integration property (covered by manual verification below).

- [ ] **Step 1: Create** `Wilgo/Features/Notifications/ModelContext+WilgoMain.swift`

```swift
import Foundation
import SwiftData

/// Reads use `mainContext` so schedule / Live Activity logic sees the same object graph as
/// `@Query` and `EditCommitmentView`. A fresh `ModelContext(container)` can observe stale store
/// state until merge/save completes — every scheduler in this folder must read through this
/// accessor, never a fresh context.
extension ModelContext {
    @MainActor
    static var wilgoMain: ModelContext {
        WilgoApp.sharedModelContainer.mainContext
    }
}
```

- [ ] **Step 2: Delete the now-duplicate private extension in NowLiveActivityManager**

Remove lines 6–15 of `NowLiveActivityManager.swift` (the `// MARK: - Model access` block with the `private extension ModelContext`). Its usages (`ModelContext.wilgoMain`) keep compiling against the new internal extension.

- [ ] **Step 3: Switch the other three schedulers to** `wilgoMain`

`SlotStartNotificationScheduler.refresh` — replace:

```swift
        let context = WilgoApp.sharedModelContainer.mainContext
```

with:

```swift
        let context = ModelContext.wilgoMain
```

`CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask` — replace:

```swift
        let context = ModelContext(WilgoApp.sharedModelContainer)
```

with:

```swift
        let context = ModelContext.wilgoMain
```

`CycleEndNotificationScheduler.refresh` — replace:

```swift
        let context = ModelContext(WilgoApp.sharedModelContainer)
```

with:

```swift
        let context = ModelContext.wilgoMain
```

(All three call sites are already `@MainActor`.)

- [ ] **Step 4: Build + run the Notifications test bundle** (same command as Commit 1 Step 8). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Wilgo/Features/Notifications/
git commit -m "Share ModelContext.wilgoMain; fix stale fresh-context reads

CatchUpReminder and CycleEndNotificationScheduler read through fresh
ModelContext(container) instances, which can observe stale store state until
merge/save completes -- exactly the hazard the (previously private) wilgoMain
comment documents. All four schedulers now read through the one accessor.

#notification
tracking: https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

**Manual verification (3Sauce, optional but recommended):** on the simulator, check in a commitment via the widget/LA, then foreground the app and confirm the catch-up notification chain reflects the check-in (previously it could briefly read pre-check-in state).

---

### Commit 3 — fireOnce(at:) trigger builder; unify on Time.calendar

> **EXECUTED DIFFERENTLY (2026-07-12, decision by 3Sauce):** the `fireOnce` helper was built,
> then judged a shallow wrapper (3-line Foundation call, 2 call sites, tests that mostly verify
> Foundation) and reverted. What landed is only the behavior fix: one line in
> `CatchUpReminder.scheduleNotificationPost`, `Calendar.current` → `Time.calendar`.
> The steps below are kept for the record of the original design.

**Files:**

- Create: `Wilgo/Features/Notifications/UNCalendarNotificationTrigger+FireOnce.swift`
- Create: `WilgoTests/Notifications/FireOnceTriggerTests.swift`
- Modify: `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` (`makeRequest`)
- Modify: `Wilgo/Features/Notifications/CatchUpReminder.swift` (`scheduleNotificationPost`)

- [ ] **Step 1: Write the failing tests**

Create `WilgoTests/Notifications/FireOnceTriggerTests.swift`:

```swift
import Foundation
import Testing
import UserNotifications
@testable import Wilgo

struct FireOnceTriggerTests {
    @Test("builds a non-repeating trigger whose components come from Time.calendar")
    func fireOnce_componentsMatchTimeCalendar() {
        let date = Date(timeIntervalSince1970: 1_752_300_000)  // fixed instant
        let trigger = UNCalendarNotificationTrigger.fireOnce(at: date)
        #expect(!trigger.repeats)
        let expected = Time.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(trigger.dateComponents == expected)
    }

    @Test("next trigger date resolves back to the requested instant")
    func fireOnce_nextTriggerDateRoundTrips() {
        let date = Time.now().addingTimeInterval(60 * 60)  // an hour from now, future-proof
        let trigger = UNCalendarNotificationTrigger.fireOnce(at: date)
        let next = trigger.nextTriggerDate()
        // Sub-second precision is intentionally dropped by the component round-trip.
        #expect(next != nil && abs(next!.timeIntervalSince(date)) < 1)
    }
}
```

- [ ] **Step 2: Run to verify compile failure** (`-only-testing:WilgoTests/FireOnceTriggerTests`): "type 'UNCalendarNotificationTrigger' has no member 'fireOnce'".

- [ ] **Step 3: Create** `Wilgo/Features/Notifications/UNCalendarNotificationTrigger+FireOnce.swift`

```swift
import Foundation
import UserNotifications

extension UNCalendarNotificationTrigger {
    /// One-shot trigger at `date`, resolved in `Time.calendar`. All schedulers in this folder
    /// must build date triggers through this: mixing calendars (`Calendar.current` vs
    /// `Time.calendar`) lets fire times silently diverge across schedulers.
    static func fireOnce(at date: Date) -> UNCalendarNotificationTrigger {
        let components = Time.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
```

- [ ] **Step 4: Run the new tests — expect PASS.**

- [ ] **Step 5: Adopt in both schedulers**

`SlotStartNotificationScheduler.makeRequest` — replace:

```swift
        let components = Time.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
```

with:

```swift
        return UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger.fireOnce(at: fireDate))
```

(Explicit type, not `.fireOnce`: the parameter's contextual type is the base `UNNotificationTrigger?`, so implicit-member lookup can't see a member defined on the subclass.)

`CatchUpReminder.scheduleNotificationPost` — replace, inside the `for (index, fireDate)` loop:

```swift
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
```

with:

```swift
            let request = UNNotificationRequest(
                identifier: "\(notificationIDPrefix)\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger.fireOnce(at: fireDate)
            )
```

Note this deliberately changes CatchUpReminder from `Calendar.current` to `Time.calendar`.

- [ ] **Step 6: Build + run the Notifications test bundle (plus FireOnceTriggerTests). Expected: PASS.**

- [ ] **Step 7: Commit**

```bash
git add Wilgo/Features/Notifications/ WilgoTests/Notifications/
git commit -m "Add UNCalendarNotificationTrigger.fireOnce(at:); unify on Time.calendar

SlotStart built one-shot triggers with Time.calendar while CatchUpReminder used
Calendar.current -- if the two ever differ (timezone/week rules), fire times
silently diverge across schedulers. Both now build through one helper.

#notification
tracking: https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Commit 4 — NotificationText.joinedTitles: shared "+N more" body format

**Files:**

- Create: `Wilgo/Features/Notifications/NotificationText.swift`
- Create: `WilgoTests/Notifications/NotificationTextTests.swift`
- Modify: `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift` (`makeMultiContent`)
- Modify: `Wilgo/Features/Notifications/CatchUpReminder.swift` (`makeNotificationContent`)

- [ ] **Step 1: Write the failing tests**

Create `WilgoTests/Notifications/NotificationTextTests.swift`:

```swift
import Testing
@testable import Wilgo

struct NotificationTextTests {
    @Test("empty list produces empty string")
    func joinedTitles_empty() {
        #expect(NotificationText.joinedTitles([]) == "")
    }

    @Test("single title passes through")
    func joinedTitles_single() {
        #expect(NotificationText.joinedTitles(["Read"]) == "Read")
    }

    @Test("up to three titles are joined with middle dots, no suffix")
    func joinedTitles_three() {
        #expect(NotificationText.joinedTitles(["A", "B", "C"]) == "A · B · C")
    }

    @Test("more than three titles get the +N more suffix")
    func joinedTitles_overflow() {
        #expect(NotificationText.joinedTitles(["A", "B", "C", "D", "E"]) == "A · B · C · +2 more")
    }
}
```

- [ ] **Step 2: Run to verify compile failure** (`-only-testing:WilgoTests/NotificationTextTests`): "cannot find 'NotificationText' in scope".

- [ ] **Step 3: Create** `Wilgo/Features/Notifications/NotificationText.swift`

```swift
/// Shared copy builders for the notification schedulers.
enum NotificationText {
    /// "A · B · C · +2 more" — the folder-wide body format for multi-commitment notifications.
    static func joinedTitles(_ titles: [String], visibleCount: Int = 3) -> String {
        let primary = titles.prefix(visibleCount).joined(separator: " · ")
        return titles.count > visibleCount
            ? "\(primary) · +\(titles.count - visibleCount) more"
            : primary
    }
}
```

- [ ] **Step 4: Run the new tests — expect PASS.**

- [ ] **Step 5: Adopt in both schedulers**

`SlotStartNotificationScheduler.makeMultiContent` — replace:

```swift
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        content.body = titles.count > 3 ? "\(primary) · +\(titles.count - 3) more" : primary
```

with:

```swift
        content.body = NotificationText.joinedTitles(commitments.map(\.title))
```

`CatchUpReminder.makeNotificationContent` — replace:

```swift
        content.title = "Catch up on \(count) commitments"
        let titles = commitments.map(\.title)
        let primary = titles.prefix(3).joined(separator: " · ")
        if titles.count > 3 {
            content.body = "\(primary) · +\(titles.count - 3) more"
        } else {
            content.body = primary
        }
        return content
```

with:

```swift
        content.title = "Catch up on \(count) commitments"
        content.body = NotificationText.joinedTitles(commitments.map(\.title))
        return content
```

- [ ] **Step 6: Build + run the Notifications test bundle (all of it). Expected: PASS.**

- [ ] **Step 7: Run the FULL suite (final commit gate)**

```bash
./test-with-cleanup.sh
```

Expected: everything passes except the known pre-existing `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()`.

- [ ] **Step 8: Commit**

```bash
git add Wilgo/Features/Notifications/ WilgoTests/Notifications/
git commit -m "Extract NotificationText.joinedTitles for the shared +N-more body format

The 'A · B · C · +N more' body builder was duplicated between
SlotStartNotificationScheduler and CatchUpReminder.

#notification
tracking: https://app.notion.com/p/DRY-the-notification-scheduling-logic-esp-the-background-one-3974b58e32c38083966ee3a36333067f?source=copy_link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 2 — BackgroundRefreshScheduler template (added 2026-07-12, pending 3Sauce review)

### Context

3Sauce: the BG-task scheduling convention is confusing to re-read — "I always need quite a bit of time reading the code again the next time I see the code." The Phase-1 helpers removed duplication but the *pattern* (register-before-submit, re-queue-before-work, complete-after-work, scene-phase watchdog) still lives only in scattered comments and three slightly different file layouts.

**Goal:** make the structure literally visible: a template-method protocol that (a) hosts the lifecycle documentation in one place, (b) structurally enforces the re-queue-before-work ordering that is currently copy-pasted discipline, and (c) reduces each scheduler's BG section to three declarations (identifier, wake policy, work).

### Design Decisions (Phase 2)

**Template-method protocol, not a parent class.** The schedulers are `enum` namespaces — no inheritance. A protocol with default implementations gives the template without converting to singleton classes.

**Why this passes the `fireOnce` bar:** unlike `fireOnce` (thin wrapper over standard API), the default `refresh()` encodes an *ordering invariant* — schedule the next wake, then do the work — that previously had to be remembered at three different places (and was, in fact, done in three different places). The protocol is also the single documented home of the mental model, which is the actual pain.

**Unified entry point name: `refresh()`** (judgment call, approved by 3Sauce to decide): matches `CycleEndNotificationScheduler.refresh()` so `CommitmentChangeRefresher.refreshAll()` reads as four identical calls. The per-scheduler work hook is `performWork()`; the wake policy is `nextWakeEarliestDate` (named for `BGAppRefreshTaskRequest.earliestBeginDate` semantics).

**CycleEnd deliberately does NOT conform** — it has no BG task (repeating calendar triggers). Non-conformance now documents that instead of looking accidental.

**Known behavior deltas (accepted):**
- `SlotStartNotificationScheduler.refresh()` now re-queues its wake on *every* call (previously only on BG fire and app-backgrounding). Harmless: `submit` replaces the pending request and `earliestBeginDate` is only a floor; the scene handler already re-submitted on every backgrounding. The now-redundant explicit `scheduleBackgroundTask()` call in `WilgoApp`'s else-branch is removed.
- `backgroundTaskIdentifier` on CatchUpReminder / NowLiveActivityManager goes from `private` to internal (protocol witness requirement).
- Entry-point renames: `updateAndScheduleNotificationAndBackgroundTask()` and `workAndScheduleNextBGTask()` disappear; all callers say `refresh()`.

### Commit 5 — Add BackgroundRefreshScheduler: the documented BG-wake template

**Files:**
- Create: `Wilgo/Features/Notifications/BackgroundRefreshScheduler.swift`
- Create: `WilgoTests/Notifications/BackgroundRefreshSchedulerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Wilgo

/// Conformer that records the order of template events. `nextWakeEarliestDate` is read
/// inside `scheduleBackgroundTask()`, so its getter marks the "schedule" step.
/// The real `BGWake.submit` runs with an unregistered identifier — it throws inside,
/// which BGWake logs and swallows; expected and harmless in the test host.
private enum RecordingScheduler: BackgroundRefreshScheduler {
    @MainActor static var events: [String] = []
    static let backgroundTaskIdentifier = "wilgo.test.recording"
    @MainActor static var nextWakeEarliestDate: Date {
        events.append("schedule")
        return Date().addingTimeInterval(60)
    }
    @MainActor static func performWork() async {
        events.append("work")
    }
}

struct BackgroundRefreshSchedulerTests {
    @Test("refresh re-queues the next wake BEFORE running the work")
    @MainActor
    func refresh_schedulesBeforeWork() async {
        RecordingScheduler.events = []
        await RecordingScheduler.refresh()
        #expect(RecordingScheduler.events == ["schedule", "work"])
    }
}
```

- [ ] **Step 2: Verify red** (SourceKit "cannot find BackgroundRefreshScheduler" or xcodebuild compile failure).

- [ ] **Step 3: Create `Wilgo/Features/Notifications/BackgroundRefreshScheduler.swift`**

```swift
import Foundation

/// THE background-wake pattern for the notification schedulers. Each conformer owns one
/// BGAppRefreshTask and one reconcile, wired together by the defaults below — a conformer
/// declares only its identifier, its wake policy, and its work.
///
/// Lifecycle (identical for every conformer):
/// 1. `WilgoApp.init` calls `registerBackgroundTask()` — must run before any submit.
/// 2. `refresh()` is the only entry point anyone calls (scene-phase handler, BG fire,
///    `CommitmentChangeRefresher.refreshAll`, CatchUp's hourly timer). It re-queues the
///    next wake FIRST — so a mid-flight kill still leaves a wake queued — then runs
///    `performWork()`. That ordering is the template's enforced invariant.
/// 3. `BGWake` completes the BGTask only after `refresh()` returns (returning means the
///    work is done) and reports failure on expiration so iOS retries.
/// 4. iOS treats `earliestBeginDate` as a floor, not a promise — BG fires are
///    best-effort. The scene-phase calls double as the watchdog that re-queues wakes
///    whenever iOS skipped one.
///
/// `CycleEndNotificationScheduler` deliberately does NOT conform: it schedules repeating
/// calendar triggers and needs no background wake.
protocol BackgroundRefreshScheduler {
    static var backgroundTaskIdentifier: String { get }
    /// Wake policy: the earliest instant iOS may launch us next.
    @MainActor static var nextWakeEarliestDate: Date { get }
    /// The reconcile itself. Returning means the work is done (BGWake awaits this).
    @MainActor static func performWork() async
}

extension BackgroundRefreshScheduler {
    /// Register the BGAppRefreshTask handler. Must be called before any submit — i.e., from
    /// `WilgoApp.init`.
    static func registerBackgroundTask() {
        BGWake.register(backgroundTaskIdentifier) { await refresh() }
    }

    /// Submit (or replace) the next wake per `nextWakeEarliestDate`.
    @MainActor
    static func scheduleBackgroundTask() {
        BGWake.submit(backgroundTaskIdentifier, earliestBeginDate: nextWakeEarliestDate)
    }

    /// The single entry point: re-queue the next wake FIRST (mid-flight kill still leaves
    /// a wake queued), then reconcile.
    @MainActor
    static func refresh() async {
        scheduleBackgroundTask()
        await performWork()
    }
}
```

- [ ] **Step 4: Run `-only-testing:WilgoTests/BackgroundRefreshSchedulerTests` — expect PASS.**

- [ ] **Step 5: Commit** (`Add BackgroundRefreshScheduler: documented template for BG-wake schedulers`, both tags + tracking + co-author, as per the footer block above).

### Commit 6 — Adopt in SlotStartNotificationScheduler

**Files:**
- Modify: `Wilgo/Features/Notifications/SlotStartNotificationScheduler.swift`
- Modify: `Wilgo/WilgoApp.swift` (remove now-redundant explicit schedule call)

- [ ] **Step 1: Conform and collapse the BG section**

Declaration becomes `enum SlotStartNotificationScheduler: BackgroundRefreshScheduler {`. Delete `registerBackgroundTask()` and `scheduleBackgroundTask()` (protocol defaults). Replace `refresh(now: Date = Time.now())` (no caller passes `now`; tests use the pure helpers) with:

```swift
    static var nextWakeEarliestDate: Date { Date().addingTimeInterval(24 * 60 * 60) }

    /// Rebuilds the pending slot-start notifications from current commitments.
    @MainActor
    static func performWork() async {
        let now = Time.now()
        let context = ModelContext.wilgoMain
        // ... (existing refresh body unchanged, using the local `now`)
    }
```

- [ ] **Step 2: WilgoApp** — delete the now-redundant line in the else-branch (`SlotStartNotificationScheduler.scheduleBackgroundTask()` plus its comment); the `Task { await SlotStartNotificationScheduler.refresh() }` call above it already re-queues.

- [ ] **Step 3: Run the Notifications test bundle — PASS. Commit** (`Adopt BackgroundRefreshScheduler in SlotStartNotificationScheduler`).

### Commit 7 — Adopt in CatchUpReminder

**Files:**
- Modify: `Wilgo/Features/Notifications/CatchUpReminder.swift`
- Modify: `Wilgo/WilgoApp.swift` (rename 2 call sites + the TODO comment's code sketch)
- Modify: `Wilgo/Features/Notifications/CommitmentChangeRefresher.swift` (rename 1 call site)

- [ ] **Step 1: Conform and collapse**

`enum CatchUpReminder: BackgroundRefreshScheduler {`; `backgroundTaskIdentifier` loses `private`. Delete `registerBackgroundTask()` and `scheduleBackgroundTask(now:)`. `updateAndScheduleNotificationAndBackgroundTask(now:)` becomes:

```swift
    static var nextWakeEarliestDate: Date { Date().addingTimeInterval(1 * 60 * 60) }

    /// Recomputes the catch-up set, updates the UserDefaults anchor, and rebuilds the
    /// notification chain. (Wake re-queuing moved to the template's refresh().)
    @MainActor
    static func performWork() async {
        let now = Time.now()
        // ... existing body, minus the scheduleBackgroundTask(now:) line ...
    }
```

The hourly `InAppScheduler` closure and all callers switch to `await CatchUpReminder.refresh()`.

- [ ] **Step 2: Run the Notifications test bundle — PASS. Commit** (`Adopt BackgroundRefreshScheduler in CatchUpReminder`).

### Commit 8 — Adopt in NowLiveActivityManager; refreshAll reads uniformly

**Files:**
- Modify: `Wilgo/Features/Notifications/NowLiveActivityManager.swift`
- Modify: `Wilgo/WilgoApp.swift` (rename 2 call sites)
- Modify: `Wilgo/Features/Notifications/CommitmentChangeRefresher.swift` (rename 1 call site)

- [ ] **Step 1: Conform and collapse**

`enum NowLiveActivityManager: BackgroundRefreshScheduler {`; identifier loses `private`. Delete `registerBackgroundTask()`, `scheduleBackgroundTask()`, `workAndScheduleNextBGTask()`. Add:

```swift
    /// Wake at the next slot edge OR cycle boundary (folded by `nextStageRefreshTime`), so
    /// the app also refreshes at the daily-cycle rollover when no slot transition precedes it.
    @MainActor
    static var nextWakeEarliestDate: Date {
        let now = Time.now()
        let commitments = (try? ModelContext.wilgoMain.fetch(.activeOnly)) ?? []
        return StageCharacterization.nextStageRefreshTime(commitments: commitments, now: now)
    }

    /// Chains a reconcile behind any in-flight one and awaits it (see `apply()` for why
    /// runs must not interleave).
    @MainActor
    static func performWork() async {
        apply()
        // `refreshTask` is read synchronously right after `apply()` on the main actor, so it
        // is exactly the run just chained — no later `apply()` can swap the chain head between.
        await refreshTask?.value
    }
```

`CommitmentChangeRefresher.refreshAll()` ends as four identical `await X.refresh()` lines + widget reload; WilgoApp's two `workAndScheduleNextBGTask()` sites become `refresh()`.

- [ ] **Step 2: Run the Notifications test bundle — PASS.**

- [ ] **Step 3: FULL suite gate: `./test-with-cleanup.sh` — everything passes (modulo the known pre-existing failure).**

- [ ] **Step 4: Commit** (`Adopt BackgroundRefreshScheduler in NowLiveActivityManager; uniform refreshAll`).

### Dependency graph (Phase 2)

```
Commit 5: protocol + ordering test
    |
Commit 6: SlotStart adoption      [sequential — WilgoApp touched by 6,7,8]
    |
Commit 7: CatchUp adoption
    |
Commit 8: NowLA adoption + uniform refreshAll + full-suite gate
```

---

## Critical Files

| File                                                              | Role                                              |
| ----------------------------------------------------------------- | ------------------------------------------------- |
| `Wilgo/Features/Notifications/BGWake.swift` (new)                 | Single home for the BGTask completion-race logic  |
| `Wilgo/Features/Notifications/ModelContext+WilgoMain.swift` (new) | The one sanctioned read context                   |
| `Wilgo/Features/Notifications/CatchUpReminder.swift`              | Receives both behavior fixes (context + calendar) |
| `WilgoTests/Notifications/BGWakeTests.swift` (new)                | First-ever coverage of the race logic             |

### Dependency Graph

```
Commit 1: BGWake extraction
    |
Commit 2: ModelContext.wilgoMain          [sequential — same files]
    |
Commit 3: fireOnce(at:) + Time.calendar   [sequential — same files]
    |
Commit 4: NotificationText.joinedTitles   [sequential — same files]
```

Logically independent, but all four touch `SlotStartNotificationScheduler.swift` / `CatchUpReminder.swift` — do not parallelize.

## Out of scope (deliberately)

- The `WilgoApp.swift` scene-phase TODO (background-time assertion) — next workstream, easier after this lands.
- The `requestAuthorization → guard granted → remove-then-add` pattern (3×) — the variants differ enough (prefix-scan vs fixed-ID cancel) that a shared helper would be shallow.
- NowLiveActivityManager rename / enum doc-comment rewrite (assessment point 2).
