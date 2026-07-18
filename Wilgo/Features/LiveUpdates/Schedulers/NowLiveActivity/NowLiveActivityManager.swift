import ActivityKit
import Foundation
import SwiftData

enum NowLiveActivityManager: BackgroundRefreshScheduler {
    static let backgroundTaskIdentifier = "wilgo.live-activity-sync"

    /// Wake at the next slot edge OR cycle boundary (folded together by `nextStageRefreshTime`), so
    /// the app also refreshes at the daily-cycle rollover when no slot transition precedes it.
    @MainActor
    static var nextWakeEarliestDate: Date {
        let now = Time.now()
        let commitments = (try? ModelContext.wilgoMain.fetch(.activeOnly)) ?? []
        return StageCharacterization.nextStageRefreshTime(commitments: commitments, now: now)
    }

    @MainActor
    private static var refreshTask: Task<Void, Never>?

    /// Chains a reconcile behind any in-flight one and awaits it.
    ///
    /// Serializes runs so no `refresh()` body starts until the previous one has fully finished —
    /// `refresh()` breaks if two runs interleave (see its doc). The chain is built by a single
    /// synchronous, `await`-free read/write on the main actor:
    ///
    /// - `previous` captures the in-flight run (if any) by value; the Task's handle reifies THIS
    ///   run as the value the next call will chain behind. (A bare `await refresh()` would leave
    ///   nothing for the next call to wait on.)
    /// - Because the read of `previous` and the write of `refreshTask` are adjacent with no `await`
    ///   between them, the swap is atomic: a later call is guaranteed to read THIS run as its
    ///   `previous` and can't slip into a gap and chain behind the wrong predecessor. The final
    ///   read of `refreshTask` is likewise exactly the run just chained.
    ///
    /// The Task body is only ENQUEUED on the main actor here, not run inline; correctness doesn't
    /// depend on WHEN it starts, only that `previous` was captured by value before it does.
    @MainActor
    static func performWork() async {
        let previous = refreshTask
        refreshTask = Task { @MainActor in
            // Gate: park this run until the previous run's `refresh()` has fully returned (including
            // all of its internal `await`s), so their bodies never interleave.
            await previous?.value
            if AppSettings.nowLiveActivityEnabled {
                await LiveActivityRefresher.refresh(context: ModelContext.wilgoMain)
            } else {
                await LiveActivityRefresher.endAll(context: ModelContext.wilgoMain)
            }
        }
        await refreshTask?.value
    }
}
