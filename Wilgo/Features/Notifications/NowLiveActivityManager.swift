import ActivityKit
import BackgroundTasks
import Foundation
import SwiftData

// MARK: - Model access

/// Reads use `mainContext` so schedule / Live Activity logic sees the same object graph as `@Query`
/// and `EditCommitmentView`. A fresh `ModelContext(container)` can observe stale store state until
/// merge/save completes.
private extension ModelContext {
    static var wilgoMain: ModelContext {
        WilgoApp.sharedModelContainer.mainContext
    }
}

enum NowLiveActivityManager {
    @MainActor
    private static var refreshTask: Task<Void, Never>?

    // Serializes runs so no `refresh()` body starts until the previous one has fully finished —
    // `refresh()` breaks if two runs interleave (see its doc). Two pieces do this:
    //
    // 1. The Task bridges sync callers into async `refresh()`, AND its handle reifies the
    //    in-flight run as a value the next call can wait on. (A bare `await refresh()`
    //    would leave nothing for the next call to chain behind.)
    // 2. The read of `previous` and the write of `refreshTask` are synchronous and adjacent —
    //    no `await` between them — so the swap is an atomic "append myself to the chain" step.
    //    A later `apply()` is therefore guaranteed to read THIS run as its `previous`; it can't
    //    slip into a gap and chain behind the wrong predecessor.
    @MainActor
    private static func apply() {
        let previous = refreshTask

        // Scheduling note: `Task { ... }` constructs the task and returns its handle synchronously,
        // so the assignment to `refreshTask` completes before the body runs. The body itself is only
        // ENQUEUED on the main actor's executor, not run inline — because `apply()` is synchronous
        // and already on the main actor, the body can't start until the current synchronous work
        // unwinds and the executor is free. Correctness does not depend on WHEN the body starts,
        // only on the synchronous read/write in point 2: whenever the body runs, `previous` has
        // already captured the prior task by value, so `await previous?.value` gates behind it.
        refreshTask = Task { @MainActor in
            // Gate: park this run until the previous run's `refresh()` has fully returned (including
            // all of its internal `await`s), so their bodies never interleave.
            await previous?.value
            await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
        }
        // IF there is statement, it would run before the refreshTask boy executes.
    }

    private static let backgroundTaskIdentifier = "wilgo.live-activity-sync"

    /// Register the BGAppRefreshTask handler. Must be called before any `submit()` — i.e., before
    /// `scheduleBackgroundTask()`.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in  // launch handler, use it to report success/failure and to attach an expiration handler.
            let work = Task { @MainActor in
                // Await the reconcile before reporting completion: `setTaskCompleted` lets iOS
                // suspend the process, and the chained run would otherwise still be in flight.
                await workAndScheduleNextBGTask()
                guard !Task.isCancelled else { return }  // if the task is cancelled (before expiration), check cancelled cooperatively to avoid `task.setTaskCompleted()` twice, which is a violation of the API.
                task.setTaskCompleted(success: true)
            }
            // If iOS reclaims the wake before the reconcile finishes, cancel and report failure
            // so the task is retried rather than silently marked done mid-flight.
            // task.expirationHandler is BGTask API's deadline callback. A background wake comes
            // with a limited runtime budget (roughly up to 30 seconds for an app-refresh task,
            // sometimes less under memory/battery pressure). If your work is still running when
            // the budget expires, iOS calls your expirationHandler as a final warning.
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Queue the next wake, request a reconcile, and await its completion (the folder-wide
    /// scheduler contract: returning means the work is done). App-alive callers may
    /// fire-and-forget with `Task { await ... }`.
    @MainActor
    static func workAndScheduleNextBGTask() async {
        // Re-schedule for the next slot boundary before doing the work so that even
        // if the process is killed mid-flight the next wakeup is already queued.
        NowLiveActivityManager.scheduleBackgroundTask()
        apply()
        // `refreshTask` is read synchronously right after `apply()` on the main actor, so it is
        // exactly the run just chained — no later `apply()` can swap the chain head in between.
        await refreshTask?.value
    }

    /// Submit (or replace) a BGAppRefreshTask that wakes the app at the next slot transition.
    /// Safe to call repeatedly — BGTaskScheduler replaces any existing request with the same identifier.
    @MainActor
    private static func scheduleBackgroundTask() {
        let now = Time.now()
        let context = ModelContext.wilgoMain
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        // Wake at the next slot edge OR cycle boundary (folded together by `nextStageRefreshTime`), so
        // the app also refreshes at the daily-cycle rollover when no slot transition precedes it.
        let nextDate =
            StageCharacterization.nextStageRefreshTime(commitments: commitments, now: now)
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = nextDate
        try? BGTaskScheduler.shared.submit(request)
    }
}
