import ActivityKit
import BackgroundTasks
import Foundation
import SwiftData

// MARK: - Model access

/// Reads use `mainContext` so schedule / Live Activity logic sees the same object graph as `@Query`
/// and `EditCommitmentView`. A fresh `ModelContext(container)` can observe stale store state until
/// merge/save completes.
extension ModelContext {
    fileprivate static var wilgoMain: ModelContext {
        WilgoApp.sharedModelContainer.mainContext
    }
}

/// Owns all Live Activity lifecycle operations (start / update / end).
/// 3. **BGAppRefreshTask** (`registerBackgroundTask` / `scheduleBackgroundTask`):
///    wakes the app at each slot boundary even when suspended or killed.
///    Scheduled on every scene-phase change and self-sustaining after each fire.
enum LiveActivityManager {
    @MainActor
    private static func apply() async {
        print("LiveActivityManager.apply()")
        let context = ModelContext.wilgoMain
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let now = Time.now()
        let current = CommitmentAndSlot.currentWithBehind(
            commitments: commitments,
            now: now,
        )

        let contentState = LiveActivityManager.makeLiveActivityContentState(from: current)
        let staleDate = current.first.map { $0.1[0].endToday }

        if let state = contentState, state.hasCurrentCommitment {
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let activity = Activity<NowAttributes>.activities.first {
                await activity.update(content)
            } else {
                do {
                    _ = try Activity.request(
                        attributes: NowAttributes(),
                        content: content,
                        pushType: nil
                    )
                } catch {
                    print(
                        "LiveActivityManager.apply() - Activity.request failed with error: \(error)"
                    )
                }

            }
        } else {
            for activity in Activity<NowAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func makeLiveActivityContentState(
        from currentSlots: [CommitmentAndSlot.WithBehind]
    ) -> NowAttributes.ContentState? {
        guard let (commitment, slots, _) = currentSlots.first else { return nil }
        let commitmentId = commitment.persistentModelID.encoded()
        let slotId = slots[0].persistentModelID.encoded()
        let secondaryTitles = currentSlots.dropFirst().map(\.commitment.title)
        return NowAttributes.ContentState(
            commitmentTitle: commitment.title,
            slotTimeText: slots[0].timeOfDayText,
            commitmentId: commitmentId,
            slotId: slotId,
            secondaryTitles: secondaryTitles
        )
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
        LiveActivityManager.scheduleBackgroundTask()
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
        let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        let nextDate =
            CommitmentAndSlot.nextTransitionDate(commitments: commitments, now: now)
            ?? now.addingTimeInterval(60 * 60)  // 1-hour fallback when there are no commitments
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = nextDate
        try? BGTaskScheduler.shared.submit(request)
    }
}
