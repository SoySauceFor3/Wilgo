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

/// Owns all Live Activity lifecycle operations (start / update / end).
/// 3. **BGAppRefreshTask** (`registerBackgroundTask` / `scheduleBackgroundTask`):
///    wakes the app at each slot boundary even when suspended or killed.
///    Scheduled on every scene-phase change and self-sustaining after each fire.
enum NowLiveActivityManager {
    @MainActor
    private static func apply() async {
        await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
    }

    private static let backgroundTaskIdentifier = "wilgo.live-activity-sync"

    /// Register the BGAppRefreshTask handler. Must be called before any `submit()` — i.e., before
    /// `scheduleBackgroundTask()`.
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
                workAndScheduleNextBGTask()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    @MainActor
    static func workAndScheduleNextBGTask() {
        // Re-schedule for the next slot boundary before doing the work so that even
        // if the process is killed mid-flight the next wakeup is already queued.
        NowLiveActivityManager.scheduleBackgroundTask()
        Task {
            await apply()
        }
    }

    /// Submit (or replace) a BGAppRefreshTask that wakes the app at the next slot transition.
    /// Safe to call repeatedly — BGTaskScheduler replaces any existing request with the same identifier.
    @MainActor
    private static func scheduleBackgroundTask() {
        let now = Time.now()
        let context = ModelContext.wilgoMain
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        let nextDate =
            StageCharacterization.nextTransitionDate(commitments: commitments, now: now)
            ?? now.addingTimeInterval(60 * 60)  // 1-hour fallback when there are no commitments
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = nextDate
        try? BGTaskScheduler.shared.submit(request)
    }
}
