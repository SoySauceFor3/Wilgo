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
    /// Serializes and coalesces reconciles. `LiveActivityRefresher.refresh()` must never run
    /// concurrently (see its doc: interleaved runs produce duplicate pending activities), and it
    /// reconciles to *current* state — so when several wake paths fire in a burst (e.g. the
    /// `.inactive` then `.background` scene-phase transitions), replaying one run per call is
    /// wasteful. `Coalescer` runs at most one in-flight reconcile plus one follow-up that observes
    /// the final state.
    @MainActor
    private static let coalescer = Coalescer {
        await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
    }

    /// Request a reconcile. Non-blocking; folds into the in-flight run if one is active.
    @MainActor
    private static func apply() {
        coalescer.trigger()
    }

    private static let backgroundTaskIdentifier = "wilgo.live-activity-sync"

    /// Register the BGAppRefreshTask handler. Must be called before any `submit()` — i.e., before
    /// `scheduleBackgroundTask()`.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            let work = Task { @MainActor in
                workAndScheduleNextBGTask()
                // Await the reconcile before reporting completion: `setTaskCompleted` lets iOS
                // suspend the process, and the coalescer's run would otherwise still be in flight.
                await coalescer.wait()
                task.setTaskCompleted(success: true)
            }
            // If iOS reclaims the wake before the reconcile finishes, cancel and report failure so
            // the task is retried rather than silently marked done mid-flight.
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Queue the next wake and request a reconcile. Fire-and-forget: the reconcile runs on the
    /// coalescer. The BG handler additionally `await coalescer.wait()`s before completing so iOS
    /// can't suspend the process mid-reconcile.
    @MainActor
    static func workAndScheduleNextBGTask() {
        // Re-schedule for the next slot boundary before doing the work so that even
        // if the process is killed mid-flight the next wakeup is already queued.
        NowLiveActivityManager.scheduleBackgroundTask()
        apply()
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
